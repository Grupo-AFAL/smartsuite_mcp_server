# frozen_string_literal: true

require_relative 'base'

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
      # @param bypass_cache [Boolean] Force API call even if cache enabled (default: false)
      # @return [Hash] Tables with count and filtered data
      # @example List all tables
      #   list_tables
      #
      # @example List tables in a solution
      #   list_tables(solution_id: "sol_123")
      #
      # @example List with specific fields
      #   list_tables(fields: ["id", "name", "structure"])
      def list_tables(solution_id: nil, fields: nil, bypass_cache: false)
        validate_optional_parameter!('fields', fields, Array) if fields

        # Try cache first if enabled and no custom fields specified
        unless should_bypass_cache?(bypass_cache) || fields&.any?
          cached_tables = @cache.get_cached_table_list(solution_id)
          cache_key = solution_id ? "solution:#{solution_id}" : 'all tables'

          if cached_tables
            log_cache_hit('tables', cached_tables.size, cache_key)
            return format_tables_response(cached_tables, fields)
          else
            log_cache_miss('tables', cache_key)
          end
        end

        # Log filtering info
        log_metric("→ Filtering tables by solution: #{solution_id}") if solution_id
        log_metric("→ Requesting specific fields: #{fields.join(', ')}") if fields&.any?

        # Build endpoint with query parameters using Base helper
        endpoint = build_endpoint('/applications/', solution: solution_id, fields: fields)

        response = api_request(:get, endpoint)

        # Cache the response if cache enabled and no custom fields
        if cache_enabled? && !bypass_cache && fields.nil?
          tables_list = extract_items_from_response(response)
          @cache.cache_table_list(solution_id, tables_list)
          cache_key = solution_id ? "solution:#{solution_id}" : 'all tables'
          log_metric("✓ Cached #{tables_list.size} tables (#{cache_key})")
        end

        format_tables_response(response, fields)
      end

      private

      # Format tables response with filtering
      #
      # @param response [Hash, Array] API response or cached tables
      # @param fields [Array<String>] Specific fields requested
      # @return [Hash] Formatted tables with count
      def format_tables_response(response, fields)
        # Handle both API response format and cached array format
        tables_list = extract_items_from_response(response) || response

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
                       'solution_id' => table['solution_id']
                     }
                   end
                 end

        result = build_collection_response(tables, :tables)
        track_response_size(result, "Found #{tables.size} tables")
      end

      public

      # Retrieves table structure with aggressive field filtering.
      #
      # Returns table metadata and field definitions with only essential
      # information. Filters out UI/display metadata to reduce token usage
      # by ~80%. Logs token savings metrics.
      #
      # @param table_id [String] Table identifier
      # @return [Hash] Table with filtered structure
      # @raise [ArgumentError] If table_id is missing
      # @example
      #   get_table("tbl_123")
      def get_table(table_id)
        validate_required_parameter!('table_id', table_id)

        log_metric("→ Getting table structure: #{table_id}")
        response = api_request(:get, "/applications/#{table_id}/")

        # Return filtered structure including only essential fields
        if response.is_a?(Hash)
          # Calculate original size for comparison
          original_structure_json = JSON.generate(response['structure'])
          original_tokens = estimate_tokens(original_structure_json)

          # Filter structure to only essential fields
          filtered_structure = response['structure'].map { |field| filter_field_structure(field) }

          result = {
            'id' => response['id'],
            'name' => response['name'],
            'solution_id' => response['solution_id'],
            'structure' => filtered_structure
          }

          tokens = estimate_tokens(JSON.generate(result))
          reduction_percent = ((original_tokens - tokens).to_f / original_tokens * 100).round(1)

          log_metric("✓ Retrieved table structure: #{filtered_structure.length} fields")
          log_metric("📊 #{original_tokens} → #{tokens} tokens (saved #{reduction_percent}%)")
          log_token_usage(tokens)
          result
        else
          response
        end
      end

      # Creates a new table (application) in a solution.
      #
      # @param solution_id [String] Solution identifier where the table will be created
      # @param name [String] Name of the new table
      # @param description [String, nil] Optional description for the table
      # @param structure [Array, nil] Optional array of field definitions for the table
      # @return [Hash] Created table details
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
      def create_table(solution_id, name, description: nil, structure: nil)
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

        log_metric("✓ Created table: #{response['name']} (#{response['id']})") if response.is_a?(Hash)

        response
      end
    end
  end
end
