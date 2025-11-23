# frozen_string_literal: true

require_relative 'base'
require_relative '../formatters/toon_formatter'

module SmartSuite
  module API
    # TableOperations handles API calls for table (application) management.
    #
    # This module provides methods for:
    # - Listing tables/applications
    # - Retrieving table structure
    # - Creating new tables
    #
    # All methods implement aggressive response filtering to minimize token usage.
    # Uses Base module for common API patterns (validation, endpoint building, cache coordination).
    module TableOperations
      include Base

      # Lists tables (applications) in the workspace.
      #
      # Optionally filters by solution_id and/or specific fields.
      # When fields are specified, only those fields are returned from the API.
      # When no fields are specified, returns only essential fields (id, name, solution_id).
      #
      # @param solution_id [String, nil] Optional solution ID to filter tables
      # @param fields [Array<String>, nil] Optional array of field slugs to include in response
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Hash] TOON/plain text string or JSON hash depending on format
      # @example List all tables (TOON format by default)
      #   list_tables
      #
      # @example List tables in a solution
      #   list_tables(solution_id: "sol_123")
      #
      # @example List with specific fields
      #   list_tables(fields: ["id", "name", "structure"])
      #
      # @example Explicit format selection
      #   list_tables(format: :json)
      def list_tables(solution_id: nil, fields: nil, format: :toon)
        validate_optional_parameter!('fields', fields, Array) if fields

        # Try cache first if enabled and no custom fields specified
        cache_key = solution_id ? "solution:#{solution_id}" : 'all tables'
        cached_tables = with_cache_check('tables', cache_key, bypass: fields&.any?) do
          @cache.get_cached_table_list(solution_id)
        end
        return format_tables_response(cached_tables, fields, format) if cached_tables

        # Log filtering info
        log_metric("→ Filtering tables by solution: #{solution_id}") if solution_id
        log_metric("→ Requesting specific fields: #{fields.join(', ')}") if fields&.any?

        # Build endpoint with query parameters using Base helper
        endpoint = build_endpoint('/applications/', solution: solution_id, fields: fields)

        response = api_request(:get, endpoint)

        # Cache the response if cache enabled and no custom fields
        if cache_enabled? && fields.nil?
          # /applications/ endpoint returns an Array directly
          tables_list = extract_items_safely(response)
          @cache.cache_table_list(solution_id, tables_list)
          log_metric("✓ Cached #{tables_list.size} tables (#{cache_key})")
        end

        format_tables_response(response, fields, format)
      end

      private

      # Format tables response with filtering
      #
      # @param response [Hash, Array] API response or cached tables
      # @param fields [Array<String>] Specific fields requested
      # @param format [Symbol] Output format: :toon or :json
      # @return [String, Hash] Formatted tables (TOON as string, JSON as hash)
      def format_tables_response(response, fields, format = :toon)
        # Handle both API response format and cached array format
        # /applications/ endpoint returns an Array directly, not a Hash with 'items' key
        tables_list = extract_items_safely(response)

        # When fields are specified, return full response from API
        # When no fields specified, filter to essential fields only (client-side optimization)
        tables = if fields && !fields.empty?
                   # User requested specific fields - return as-is
                   tables_list
                 else
                   # No fields specified - apply client-side filtering for essential fields only
                   tables_list.map do |table|
                     {
                       'id' => table['id'],
                       'name' => table['name'],
                       # API returns 'solution' but we normalize to 'solution_id'
                       'solution_id' => table['solution'] || table['solution_id']
                     }
                   end
                 end

        format_tables_output(tables, format, "Found #{tables.size} tables")
      end

      # Format tables output based on format parameter
      #
      # @param tables [Array<Hash>] Filtered tables data
      # @param format [Symbol] Output format (:toon or :json)
      # @param message [String] Log message
      # @return [String, Hash] Formatted output
      def format_tables_output(tables, format, message)
        case format
        when :toon
          result = SmartSuite::Formatters::ToonFormatter.format_tables(tables)
          log_metric("✓ #{message}")
          log_metric('📊 TOON format (~50-60% token savings)')
          result
        else # :json
          result = build_collection_response(tables, :tables)
          track_response_size(result, message)
        end
      end

      public

      # Retrieves table structure with aggressive field filtering.
      #
      # Returns table metadata and field definitions with only essential
      # information. Filters out UI/display metadata to reduce token usage
      # by ~80%. Logs token savings metrics.
      #
      # @param table_id [String] Table identifier
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Table with filtered structure in requested format
      # @raise [ArgumentError] If table_id is missing
      # @example
      #   get_table("tbl_123")
      #   get_table("tbl_123", format: :json)
      def get_table(table_id, format: :toon)
        validate_required_parameter!('table_id', table_id)

        result = nil

        # Try to get from cache first
        if @cache
          cached_table = @cache.get_cached_table(table_id)
          if cached_table
            # Filter structure to only essential fields (cache has full structure)
            filtered_structure = cached_table['structure'].map { |field| filter_field_structure(field) }
            cached_table['structure'] = filtered_structure
            result = cached_table
          end
        end

        unless result
          # Cache miss - fetch from API
          log_metric("→ Getting table structure from API: #{table_id}")
          response = api_request(:get, "/applications/#{table_id}/")

          # Return filtered structure including only essential fields
          return response unless response.is_a?(Hash)

          # Filter structure to only essential fields
          filtered_structure = response['structure'].map { |field| filter_field_structure(field) }

          result = {
            'id' => response['id'],
            'name' => response['name'],
            # API returns 'solution' but we normalize to 'solution_id'
            'solution_id' => response['solution'] || response['solution_id'],
            'structure' => filtered_structure
          }
        end

        format_single_response(result, format, "Retrieved table: #{table_id} (#{result['structure'].length} fields)")
      end

      # Creates a new table (application) in a solution.
      #
      # @param solution_id [String] Solution identifier where the table will be created
      # @param name [String] Name of the new table
      # @param description [String, nil] Optional description for the table
      # @param structure [Array, nil] Optional array of field definitions for the table
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Created table details in requested format
      # @raise [ArgumentError] If required parameters are missing
      # @example Basic table
      #   create_table("sol_123", "Customers")
      #
      # @example Table with description and structure
      #   create_table("sol_123", "Tasks",
      #                description: "Project tasks tracker",
      #                structure: [
      #                  {"slug" => "title", "label" => "Title", "field_type" => "textfield"}
      #                ])
      def create_table(solution_id, name, description: nil, structure: nil, format: :toon)
        validate_required_parameter!('solution_id', solution_id)
        validate_required_parameter!('name', name)
        validate_optional_parameter!('structure', structure, Array) if structure

        log_metric("→ Creating table: #{name} in solution: #{solution_id}")

        body = {
          'name' => name,
          'solution' => solution_id,
          'structure' => structure || []
        }

        body['description'] = description if description

        response = api_request(:post, '/applications/', body)

        return response unless response.is_a?(Hash)

        format_single_response(response, format, "Created table: #{response['name']} (#{response['id']})")
      end
    end
  end
end
