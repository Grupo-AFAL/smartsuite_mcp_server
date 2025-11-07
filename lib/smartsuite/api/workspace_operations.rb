require 'time'
require 'uri'

module SmartSuite
  module API
    # WorkspaceOperations handles API calls for workspace-level operations.
    #
    # This module provides methods for:
    # - Listing and retrieving solutions
    # - Analyzing solution usage patterns
    #
    # All methods implement aggressive response filtering to minimize token usage.
    module WorkspaceOperations
      # Lists all solutions in the workspace.
      #
      # Filters response to only include essential fields (id, name, logo) by default.
      # Set include_activity_data: true to include usage metrics for identifying inactive solutions.
      # Or specify fields array to request specific fields from the API.
      # Tracks token usage and logs metrics.
      #
      # @param include_activity_data [Boolean] Include activity/usage fields (default: false)
      # @param fields [Array<String>] Specific fields to request from API (optional)
      # @return [Hash] Solutions with count and filtered data
      def list_solutions(include_activity_data: false, fields: nil)
        # Build query parameters
        query_params = []
        if fields && fields.is_a?(Array)
          fields.each { |field| query_params << "fields=#{URI.encode_www_form_component(field)}" }
        end

        endpoint = '/solutions/'
        endpoint += "?#{query_params.join('&')}" unless query_params.empty?

        log_metric("→ Requesting endpoint: #{endpoint}") if fields && !fields.empty?

        response = api_request(:get, endpoint)

        # Debug: log what fields we got back
        if fields && !fields.empty? && response.is_a?(Hash) && response['items'] && response['items'].first
          log_metric("→ API returned fields: #{response['items'].first.keys.join(', ')}")
        elsif fields && !fields.empty? && response.is_a?(Array) && response.first
          log_metric("→ API returned fields: #{response.first.keys.join(', ')}")
        end

        # If fields parameter was specified, filter response to only requested fields (client-side)
        # Note: /solutions/ endpoint doesn't respect fields parameter like /applications/ does
        if fields && !fields.empty?
          solutions_list = response.is_a?(Hash) && response['items'] ? response['items'] : response

          # Filter each solution to only include requested fields
          filtered_solutions = solutions_list.map do |solution|
            filtered = {}
            fields.each do |field|
              filtered[field] = solution[field] if solution.key?(field)
            end
            filtered
          end

          result = { 'solutions' => filtered_solutions, 'count' => filtered_solutions.size }
          tokens = estimate_tokens(JSON.generate(result))
          log_metric("✓ Found #{filtered_solutions.size} solutions with custom fields (client-side filtered)")
          log_token_usage(tokens)
          return result
        end

        # Extract only essential fields to reduce response size (client-side filtering)
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

      # Lists solutions owned by a specific user.
      #
      # Fetches all solutions with permissions data, filters client-side by owner,
      # and returns only essential fields to minimize token usage.
      #
      # @param owner_id [String] User ID of the solution owner
      # @param include_activity_data [Boolean] Include activity/usage metrics (default: false)
      # @return [Hash] Solutions owned by the specified user with count
      def list_solutions_by_owner(owner_id, include_activity_data: false)
        log_metric("→ Listing solutions owned by user: #{owner_id}")

        # Fetch all solutions (this gets full data including permissions)
        endpoint = '/solutions/'
        response = api_request(:get, endpoint)

        solutions_list = response.is_a?(Hash) && response['items'] ? response['items'] : response

        # Filter solutions where the user is in the owners array
        owned_solutions = solutions_list.select do |solution|
          solution['permissions'] &&
            solution['permissions']['owners'] &&
            solution['permissions']['owners'].include?(owner_id)
        end

        # Extract only essential fields to reduce response size
        filtered_solutions = owned_solutions.map do |solution|
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
              'has_demo_data' => solution['has_demo_data']
            })
          end

          base_fields
        end

        result = { 'solutions' => filtered_solutions, 'count' => filtered_solutions.size }
        tokens = estimate_tokens(JSON.generate(result))
        log_metric("✓ Found #{filtered_solutions.size} solutions owned by user #{owner_id}")
        log_token_usage(tokens)
        result
      end

      # Gets the most recent record update timestamp across all tables in a solution.
      #
      # Queries each table in the solution to find the most recently updated record,
      # returning the latest update timestamp across all tables.
      #
      # @param solution_id [String] Solution identifier
      # @return [String, nil] ISO8601 timestamp of most recent record update, or nil if no records
      def get_solution_most_recent_record_update(solution_id)
        # Get all tables for this solution
        tables_response = list_tables(solution_id: solution_id)

        return nil unless tables_response['tables'] && !tables_response['tables'].empty?

        most_recent_update = nil

        tables_response['tables'].each do |table|
          # Call API directly to get raw JSON response (list_records returns plain text by default)
          query_params = "?limit=1&offset=0"
          body = {
            sort: [{'field' => 'last_updated', 'direction' => 'desc'}]
          }

          records_response = api_request(:post, "/applications/#{table['id']}/records/list/#{query_params}", body)

          # Records are in items array, last_updated date is at last_updated.on
          if records_response['items'] && records_response['items'].first
            record = records_response['items'].first
            record_update = record.dig('last_updated', 'on')
            if record_update && (most_recent_update.nil? || record_update > most_recent_update)
              most_recent_update = record_update
            end
          end
        end

        most_recent_update
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
          # Focus on last_access date - demo data presence doesn't indicate usage
          records_count = solution['records_count'].to_i
          automation_count = solution['automation_count'].to_i

          if solution['last_access'].nil? || days_since_access.nil?
            # Never accessed - highest priority for cleanup
            if records_count < min_records && automation_count == 0
              inactive << category_info.merge('reason' => 'Never accessed, minimal records, no automations')
            else
              potentially_unused << category_info.merge('reason' => 'Never accessed but has content (may be template or abandoned)')
            end
          elsif days_since_access >= days_inactive
            # Not accessed in threshold period
            if records_count < min_records && automation_count == 0
              inactive << category_info.merge('reason' => "Not accessed in #{days_since_access} days, minimal records")
            else
              potentially_unused << category_info.merge('reason' => "Not accessed in #{days_since_access} days but has content")
            end
          else
            # Recently accessed - in active use
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
