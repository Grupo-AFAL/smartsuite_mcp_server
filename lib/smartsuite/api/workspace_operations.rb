require 'time'

module SmartSuite
  module API
    # WorkspaceOperations handles API calls for workspace-level operations.
    #
    # This module provides methods for:
    # - Listing and retrieving solutions
    # - Analyzing solution usage patterns
    # - Listing and retrieving tables/applications
    #
    # All methods implement aggressive response filtering to minimize token usage.
    module WorkspaceOperations
      # Lists all solutions in the workspace.
      #
      # Filters response to only include essential fields (id, name, logo) by default.
      # Set include_activity_data: true to include usage metrics for identifying inactive solutions.
      # Tracks token usage and logs metrics.
      #
      # @param include_activity_data [Boolean] Include activity/usage fields (default: false)
      # @return [Hash] Solutions with count and filtered data
      def list_solutions(include_activity_data: false)
        response = api_request(:get, '/solutions/')

        # Extract only essential fields to reduce response size
        if response.is_a?(Hash) && response['items'].is_a?(Array)
          solutions = response['items'].map do |solution|
            base_fields = {
              'id' => solution['id'],
              'name' => solution['name'],
              'logo_icon' => solution['logo_icon'],
              'logo_color' => solution['logo_color']
            }

            # Add activity/usage fields if requested
            if include_activity_data
              base_fields.merge!({
                'status' => solution['status'],
                'hidden' => solution['hidden'],
                'last_access' => solution['last_access'],
                'updated' => solution['updated'],
                'created' => solution['created'],
                'records_count' => solution['records_count'],
                'members_count' => solution['members_count'],
                'applications_count' => solution['applications_count'],
                'automation_count' => solution['automation_count'],
                'has_demo_data' => solution['has_demo_data'],
                'delete_date' => solution['delete_date'],
                'deleted_by' => solution['deleted_by'],
                'updated_by' => solution['updated_by']
              })
            end

            base_fields
          end
          result = { 'solutions' => solutions, 'count' => solutions.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{solutions.size} solutions")
          log_token_usage(tokens)
          result
        elsif response.is_a?(Array)
          # If response is directly an array
          solutions = response.map do |solution|
            base_fields = {
              'id' => solution['id'],
              'name' => solution['name'],
              'logo_icon' => solution['logo_icon'],
              'logo_color' => solution['logo_color']
            }

            # Add activity/usage fields if requested
            if include_activity_data
              base_fields.merge!({
                'status' => solution['status'],
                'hidden' => solution['hidden'],
                'last_access' => solution['last_access'],
                'updated' => solution['updated'],
                'created' => solution['created'],
                'records_count' => solution['records_count'],
                'members_count' => solution['members_count'],
                'applications_count' => solution['applications_count'],
                'automation_count' => solution['automation_count'],
                'has_demo_data' => solution['has_demo_data'],
                'delete_date' => solution['delete_date'],
                'deleted_by' => solution['deleted_by'],
                'updated_by' => solution['updated_by']
              })
            end

            base_fields
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

      # Analyzes solution usage to identify inactive solutions.
      #
      # Returns solutions categorized by usage level based on configurable thresholds.
      # Useful for identifying candidates for archival or cleanup.
      #
      # @param days_inactive [Integer] Days since last access to consider inactive (default: 90)
      # @param min_records [Integer] Minimum records to not be considered empty (default: 10)
      # @return [Hash] Solutions categorized by usage with analysis
      def analyze_solution_usage(days_inactive: 90, min_records: 10)
        log_metric("→ Analyzing solution usage (inactive: #{days_inactive} days, min_records: #{min_records})")

        # Get all solutions with activity data
        solutions_data = list_solutions(include_activity_data: true)
        return solutions_data unless solutions_data.is_a?(Hash) && solutions_data['solutions']

        solutions = solutions_data['solutions']
        current_time = Time.now

        # Categorize solutions
        inactive = []
        potentially_unused = []
        active = []

        solutions.each do |solution|
          # Skip already deleted or scheduled for deletion
          next if solution['delete_date'] || solution['deleted_by']

          # Parse last_access date
          last_access_time = solution['last_access'] ? Time.parse(solution['last_access']) : nil
          days_since_access = last_access_time ? ((current_time - last_access_time) / 86400).to_i : nil

          # Determine category
          category_info = {
            'id' => solution['id'],
            'name' => solution['name'],
            'status' => solution['status'],
            'hidden' => solution['hidden'],
            'last_access' => solution['last_access'],
            'days_since_access' => days_since_access,
            'records_count' => solution['records_count'],
            'members_count' => solution['members_count'],
            'applications_count' => solution['applications_count'],
            'automation_count' => solution['automation_count'],
            'has_demo_data' => solution['has_demo_data']
          }

          # Categorization logic
          records_count = solution['records_count'].to_i
          automation_count = solution['automation_count'].to_i

          if solution['last_access'].nil? || days_since_access.nil?
            # Never accessed
            if records_count < min_records && automation_count == 0
              inactive << category_info.merge('reason' => 'Never accessed, minimal records, no automations')
            else
              potentially_unused << category_info.merge('reason' => 'Never accessed but has some activity')
            end
          elsif days_since_access >= days_inactive
            # Not accessed in threshold period
            if records_count < min_records && automation_count == 0
              inactive << category_info.merge('reason' => "Not accessed in #{days_since_access} days, minimal records")
            else
              potentially_unused << category_info.merge('reason' => "Not accessed in #{days_since_access} days")
            end
          else
            # Recently accessed
            active << category_info
          end
        end

        result = {
          'analysis_date' => current_time.iso8601,
          'thresholds' => {
            'days_inactive' => days_inactive,
            'min_records' => min_records
          },
          'summary' => {
            'total_solutions' => solutions.size,
            'inactive_count' => inactive.size,
            'potentially_unused_count' => potentially_unused.size,
            'active_count' => active.size
          },
          'inactive_solutions' => inactive.sort_by { |s| s['days_since_access'] || Float::INFINITY }.reverse,
          'potentially_unused_solutions' => potentially_unused.sort_by { |s| s['days_since_access'] || Float::INFINITY }.reverse,
          'active_solutions_count' => active.size
        }

        tokens = estimate_tokens(JSON.generate(result))
        log_metric("✓ Analysis complete: #{inactive.size} inactive, #{potentially_unused.size} potentially unused, #{active.size} active")
        log_token_usage(tokens)
        result
      end
    end
  end
end
