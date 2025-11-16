# frozen_string_literal: true

require 'time'
require_relative 'base'

module SmartSuite
  module API
    # WorkspaceOperations handles API calls for workspace-level operations.
    #
    # This module provides methods for:
    # - Listing and retrieving solutions
    # - Analyzing solution usage patterns
    #
    # All methods implement aggressive response filtering to minimize token usage.
    # Uses Base module for common API patterns (validation, endpoint building, cache coordination, response tracking).
    module WorkspaceOperations
      include Base
      # Lists all solutions in the workspace.
      #
      # Filters response to only include essential fields (id, name, logo) by default.
      # Set include_activity_data: true to include usage metrics for identifying inactive solutions.
      # Or specify fields array to request specific fields from the API.
      # Tracks token usage and logs metrics.
      #
      # @param include_activity_data [Boolean] Include activity/usage fields (default: false)
      # @param fields [Array<String>] Specific fields to request from API (optional)
      # @param bypass_cache [Boolean] Force API call even if cache enabled (default: false)
      # @return [Hash] Solutions with count and filtered data
      # @example List all solutions
      #   list_solutions
      #
      # @example List with activity data
      #   list_solutions(include_activity_data: true)
      #
      # @example List with specific fields
      #   list_solutions(fields: ['id', 'name', 'permissions'])
      def list_solutions(include_activity_data: false, fields: nil, bypass_cache: false)
        # Try cache first if enabled and no custom fields specified
        # (custom fields parameter doesn't work with API, so we fetch full data either way)
        unless should_bypass_cache?(bypass_cache) || fields
          cached_solutions = @cache.get_cached_solutions
          if cached_solutions
            log_cache_hit('solutions', cached_solutions.size)
            return format_solutions_response(cached_solutions, include_activity_data, fields)
          else
            log_cache_miss('solutions')
          end
        end

        # Build endpoint with query parameters using Base helper
        endpoint = build_endpoint('/solutions/', fields: fields)

        log_metric("→ Requesting endpoint: #{endpoint}") if fields && !fields.empty?

        response = api_request(:get, endpoint)

        # Cache the full response if cache enabled and no custom fields
        if cache_enabled? && !bypass_cache && fields.nil?
          solutions_list = response.is_a?(Array) ? response : extract_items_from_response(response)
          @cache.cache_solutions(solutions_list)
          log_metric("✓ Cached #{solutions_list.size} solutions")
        end

        format_solutions_response(response, include_activity_data, fields)
      end

      private

      # Format solutions response with filtering
      #
      # @param response [Hash, Array] API response or cached solutions
      # @param include_activity_data [Boolean] Include activity/usage fields
      # @param fields [Array<String>] Specific fields to request
      # @return [Hash] Formatted solutions with count
      def format_solutions_response(response, include_activity_data, fields)
        # Handle both API response format and cached array format
        solutions_list = if response.is_a?(Array)
                           response
                         else
                           extract_items_from_response(response)
                         end

        # Debug: log what fields we got back
        if fields && !fields.empty? && solutions_list.is_a?(Array) && solutions_list.first
          log_metric("→ Returned fields: #{solutions_list.first.keys.join(', ')}")
        end

        # If fields parameter was specified, filter response to only requested fields (client-side)
        # Note: /solutions/ endpoint doesn't respect fields parameter like /applications/ does
        if fields && !fields.empty?
          # Filter each solution to only include requested fields
          filtered_solutions = solutions_list.map do |solution|
            filtered = {}
            fields.each do |field|
              filtered[field] = solution[field] if solution.key?(field)
            end
            filtered
          end

          result = build_collection_response(filtered_solutions, :solutions)
          return track_response_size(result, "Found #{filtered_solutions.size} solutions with custom fields (client-side filtered)")
        end

        # Extract only essential fields to reduce response size (client-side filtering)
        solutions = solutions_list.map do |solution|
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

        result = build_collection_response(solutions, :solutions)
        track_response_size(result, "Found #{solutions.size} solutions")
      end

      public

      # Retrieves a specific solution by ID.
      #
      # @param solution_id [String] Solution identifier
      # @return [Hash] Full solution details
      # @raise [ArgumentError] If solution_id is missing
      # @example
      #   get_solution('sol_123')
      def get_solution(solution_id)
        validate_required_parameter!('solution_id', solution_id)

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
      # @raise [ArgumentError] If owner_id is missing
      # @example
      #   list_solutions_by_owner('user_abc')
      #   list_solutions_by_owner('user_abc', include_activity_data: true)
      def list_solutions_by_owner(owner_id, include_activity_data: false)
        validate_required_parameter!('owner_id', owner_id)

        log_metric("→ Listing solutions owned by user: #{owner_id}")

        # Fetch all solutions (this gets full data including permissions)
        response = api_request(:get, '/solutions/')

        solutions_list = response.is_a?(Array) ? response : extract_items_from_response(response)

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

        result = build_collection_response(filtered_solutions, :solutions)
        track_response_size(result, "Found #{filtered_solutions.size} solutions owned by user #{owner_id}")
      end

      # Gets the most recent record update timestamp across all tables in a solution.
      #
      # Queries each table in the solution to find the most recently updated record,
      # returning the latest update timestamp across all tables.
      #
      # @param solution_id [String] Solution identifier
      # @return [String, nil] ISO8601 timestamp of most recent record update, or nil if no records
      # @raise [ArgumentError] If solution_id is missing
      # @example
      #   get_solution_most_recent_record_update('sol_123')
      def get_solution_most_recent_record_update(solution_id)
        validate_required_parameter!('solution_id', solution_id)

        # Get all tables for this solution
        tables_response = list_tables(solution_id: solution_id)

        return nil unless tables_response['tables'] && !tables_response['tables'].empty?

        most_recent_update = nil

        tables_response['tables'].each do |table|
          # Call API directly to get raw JSON response (list_records returns plain text by default)
          base_path = "/applications/#{table['id']}/records/list/"
          endpoint = build_endpoint(base_path, limit: 1, offset: 0)
          body = {
            sort: [{ 'field' => 'last_updated', 'direction' => 'desc' }]
          }

          records_response = api_request(:post, endpoint, body)

          # Records are in items array, last_updated date is at last_updated.on
          next unless records_response['items']&.first

          record = records_response['items'].first
          record_update = record.dig('last_updated', 'on')
          most_recent_update = record_update if record_update && (most_recent_update.nil? || record_update > most_recent_update)
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
      # @example
      #   analyze_solution_usage
      #   analyze_solution_usage(days_inactive: 60, min_records: 5)
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
          days_since_access = last_access_time ? ((current_time - last_access_time) / 86_400).to_i : nil

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
            if records_count < min_records && automation_count.zero?
              inactive << category_info.merge('reason' => 'Never accessed, minimal records, no automations')
            else
              potentially_unused << category_info.merge('reason' => 'Never accessed but has content (may be template or abandoned)')
            end
          elsif days_since_access >= days_inactive
            # Not accessed in threshold period
            if records_count < min_records && automation_count.zero?
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
          'potentially_unused_solutions' => potentially_unused.sort_by do |s|
            s['days_since_access'] || Float::INFINITY
          end.reverse,
          'active_solutions_count' => active.size
        }

        track_response_size(result, "Analysis complete: #{inactive.size} inactive, #{potentially_unused.size} potentially unused, #{active.size} active")
      end
    end
  end
end
