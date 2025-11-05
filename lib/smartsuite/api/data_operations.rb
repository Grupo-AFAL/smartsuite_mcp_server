module SmartSuite
  module API
    # DataOperations handles API calls for workspace data structures.
    #
    # This module provides methods for:
    # - Listing and retrieving solutions
    # - Listing and retrieving tables/applications
    #
    # All methods implement aggressive response filtering to minimize token usage.
    module DataOperations
      # Lists all solutions in the workspace.
      #
      # Filters response to only include essential fields (id, name, logo).
      # Tracks token usage and logs metrics.
      #
      # @return [Hash] Solutions with count and filtered data
      def list_solutions
        response = api_request(:get, '/solutions/')

        # Extract only essential fields to reduce response size
        if response.is_a?(Hash) && response['items'].is_a?(Array)
          solutions = response['items'].map do |solution|
            {
              'id' => solution['id'],
              'name' => solution['name'],
              'logo_icon' => solution['logo_icon'],
              'logo_color' => solution['logo_color']
            }
          end
          result = { 'solutions' => solutions, 'count' => solutions.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{solutions.size} solutions")
          log_token_usage(tokens)
          result
        elsif response.is_a?(Array)
          # If response is directly an array
          solutions = response.map do |solution|
            {
              'id' => solution['id'],
              'name' => solution['name'],
              'logo_icon' => solution['logo_icon'],
              'logo_color' => solution['logo_color']
            }
          end
          result = { 'solutions' => solutions, 'count' => solutions.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{solutions.size} solutions")
          log_token_usage(tokens)
          result
        else
          # Return raw response if structure is unexpected
          response
        end
      end

      # Retrieves a specific solution by ID.
      #
      # @param solution_id [String] Solution identifier
      # @return [Hash] Full solution details
      def get_solution(solution_id)
        log_metric("→ Getting solution details: #{solution_id}")
        api_request(:get, "/solutions/#{solution_id}/")
      end

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
    end
  end
end
