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
    module TableOperations
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
      def list_tables(solution_id: nil, fields: nil, bypass_cache: false)
        # Try cache first if enabled and no custom fields specified
        if cache_enabled? && !bypass_cache && (fields.nil? || fields.empty?)
          cached_tables = @cache.get_cached_table_list(solution_id)
          if cached_tables
            cache_key = solution_id ? "solution:#{solution_id}" : "all tables"
            log_metric("✓ Cache hit: #{cached_tables.size} tables (#{cache_key})")
            return format_tables_response(cached_tables, fields)
          else
            cache_key = solution_id ? "solution:#{solution_id}" : "all tables"
            log_metric("→ Cache miss for #{cache_key}, fetching from API...")
          end
        end

        # Build endpoint with query parameters
        query_params = []

        if solution_id
          query_params << "solution=#{solution_id}"
          log_metric("→ Filtering tables by solution: #{solution_id}")
        end

        # Add fields parameters (can be repeated)
        if fields && !fields.empty?
          fields.each do |field|
            query_params << "fields=#{field}"
          end
          log_metric("→ Requesting specific fields: #{fields.join(', ')}")
        end

        endpoint = '/applications/'
        endpoint += "?#{query_params.join('&')}" unless query_params.empty?

        response = api_request(:get, endpoint)

        # Cache the response if cache enabled and no custom fields
        if cache_enabled? && (fields.nil? || fields.empty?)
          tables_list = response.is_a?(Hash) && response['items'] ? response['items'] : response
          @cache.cache_table_list(solution_id, tables_list)
          cache_key = solution_id ? "solution:#{solution_id}" : "all tables"
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
        tables_list = response.is_a?(Hash) && response['items'] ? response['items'] : response

        # When fields are specified, return full response from API
        # When no fields specified, filter to essential fields only (client-side optimization)
        if fields && !fields.empty?
          # User requested specific fields - return as-is
          tables = tables_list
        else
          # No fields specified - apply client-side filtering for essential fields only
          tables = tables_list.map do |table|
            {
              'id' => table['id'],
              'name' => table['name'],
              'solution_id' => table['solution_id']
            }
          end
        end

        result = { 'tables' => tables, 'count' => tables.size }
        tokens = estimate_tokens(JSON.generate(result))
        log_metric("✓ Found #{tables.size} tables")
        log_token_usage(tokens)
        result
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
      def get_table(table_id)
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
      def create_table(solution_id, name, description: nil, structure: nil)
        log_metric("→ Creating table: #{name} in solution: #{solution_id}")

        body = {
          'name' => name,
          'solution' => solution_id,
          'structure' => structure || []
        }

        body['description'] = description if description

        response = api_request(:post, '/applications/', body)

        if response.is_a?(Hash)
          log_metric("✓ Created table: #{response['name']} (#{response['id']})")
        end

        response
      end
    end
  end
end
