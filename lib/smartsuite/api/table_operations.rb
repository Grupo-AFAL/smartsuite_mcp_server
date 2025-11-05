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
      # Filters response to only include essential fields (id, name, solution_id).
      # Optionally filters by solution_id to show only tables in that solution.
      #
      # @param solution_id [String, nil] Optional solution ID to filter tables
      # @return [Hash] Tables with count and filtered data
      def list_tables(solution_id: nil)
        # Build endpoint with query parameter if solution_id is provided
        endpoint = '/applications/'
        if solution_id
          endpoint += "?solution=#{solution_id}"
          log_metric("→ Filtering tables by solution: #{solution_id}")
        end

        response = api_request(:get, endpoint)

        # Extract only essential fields to reduce response size
        if response.is_a?(Hash) && response['items'].is_a?(Array)
          tables = response['items'].map do |table|
            {
              'id' => table['id'],
              'name' => table['name'],
              'solution_id' => table['solution_id']
            }
          end

          result = { 'tables' => tables, 'count' => tables.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{tables.size} tables")
          log_token_usage(tokens)
          result
        elsif response.is_a?(Array)
          # If response is directly an array
          tables = response.map do |table|
            {
              'id' => table['id'],
              'name' => table['name'],
              'solution_id' => table['solution_id']
            }
          end

          result = { 'tables' => tables, 'count' => tables.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{tables.size} tables")
          log_token_usage(tokens)
          result
        else
          # Return raw response if structure is unexpected
          response
        end
      end

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
