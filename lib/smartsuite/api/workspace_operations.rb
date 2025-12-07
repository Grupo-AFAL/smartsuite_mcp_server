# frozen_string_literal: true

require 'time'
require_relative 'base'
require_relative '../fuzzy_matcher'
require_relative '../formatters/toon_formatter'

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

      # Valid hex colors for solution logos (from SmartSuite API documentation)
      VALID_SOLUTION_COLORS = %w[
        #3A86FF #4ECCFD #3EAC40 #FF5757 #FF9210
        #FFB938 #883CD0 #EC506E #17C4C4 #6A849B
        #0C41F3 #00B3FA #199A27 #F1273F #FF702E
        #FDA80D #673DB6 #CD286A #00B2A8 #50515B
      ].freeze

      # Lists all solutions in the workspace.
      #
      # Filters response to only include essential fields (id, name, logo) by default.
      # Set include_activity_data: true to include usage metrics for identifying inactive solutions.
      # Or specify fields array for client-side filtering (API doesn't support field selection).
      # Supports fuzzy name search with typo tolerance.
      # Tracks token usage and logs metrics.
      #
      # @param include_activity_data [Boolean] Include activity/usage fields (default: false)
      # @param fields [Array<String>] Specific fields to return (client-side filtered, optional)
      # @param name [String] Filter by solution name using fuzzy matching (optional)
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Hash] TOON/plain text string or JSON hash depending on format
      # @example List all solutions (TOON format by default)
      #   list_solutions
      #
      # @example List with activity data
      #   list_solutions(include_activity_data: true)
      #
      # @example List with specific fields
      #   list_solutions(fields: ['id', 'name', 'permissions'])
      #
      # @example Fuzzy search by name
      #   list_solutions(name: 'desarollo')  # Matches "Desarrollos de software"
      #   list_solutions(name: 'gestion')    # Matches "Gestión de Proyectos"
      #
      # @example Explicit format selection
      #   list_solutions(format: :json)  # JSON format
      def list_solutions(include_activity_data: false, fields: nil, name: nil, format: :toon)
        # Try cache first if enabled
        # Note: Even if fields parameter is specified, we use cache and filter client-side
        # because the /solutions/ API endpoint doesn't respect the fields parameter anyway
        # Note: Name filtering happens at DB layer using custom fuzzy_match SQLite function
        cached_solutions = with_cache_check('solutions') { @cache.get_cached_solutions(name: name) }
        if cached_solutions
          log_metric("→ Fuzzy matched #{cached_solutions.size} solutions for: #{name}") if name
          return format_solutions_response(cached_solutions, include_activity_data, fields, nil, format)
        end

        # Build endpoint with query parameters using Base helper
        endpoint = build_endpoint('/solutions/', fields: fields)

        response = api_request(:get, endpoint)

        # Cache the full response if cache enabled
        # Note: We cache regardless of fields parameter since API returns full data anyway
        if cache_enabled?
          solutions_list = extract_items_safely(response)
          @cache.cache_solutions(solutions_list)
          log_metric("✓ Cached #{solutions_list.size} solutions")
        end

        # Format and filter response (including name filtering for non-cached responses)
        format_solutions_response(response, include_activity_data, fields, name, format)
      end

      private

      # Format solutions response with filtering
      #
      # @param response [Hash, Array] API response or cached solutions
      # @param include_activity_data [Boolean] Include activity/usage fields
      # @param fields [Array<String>] Specific fields to request
      # @param name [String, nil] Name filter for fuzzy matching
      # @param format [Symbol] Output format: :toon or :json
      # @return [String, Hash] Formatted solutions (TOON as string, JSON as hash)
      def format_solutions_response(response, include_activity_data, fields, name = nil, format = :toon)
        # Handle both API response format and cached array format
        solutions_list = extract_items_safely(response)

        # Apply name filtering using fuzzy matching (for non-cached responses)
        # Cached responses are already filtered at DB layer
        if name && !solutions_list.empty?
          original_count = solutions_list.size
          solutions_list = solutions_list.select do |solution|
            SmartSuite::FuzzyMatcher.match?(solution['name'], name)
          end
          log_metric("→ Fuzzy matched #{solutions_list.size}/#{original_count} solutions for: #{name}")
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

          return format_solutions_output(filtered_solutions, format)
        end

        # Extract only essential fields to reduce response size (client-side filtering)
        solutions = solutions_list.map do |solution|
          extract_essential_solution_fields(solution, include_activity_data: include_activity_data)
        end

        format_solutions_output(solutions, format)
      end

      # Format solutions output based on format parameter
      #
      # @param solutions [Array<Hash>] Filtered solutions data
      # @param format [Symbol] Output format (:toon or :json)
      # @return [String, Hash] Formatted output
      def format_solutions_output(solutions, format)
        case format
        when :toon
          SmartSuite::Formatters::ToonFormatter.format_solutions(solutions)
        else # :json
          build_collection_response(solutions, :solutions)
        end
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

        api_request(:get, "/solutions/#{solution_id}/")
      end

      # Creates a new solution in the workspace.
      #
      # @param name [String] Name of the solution (required)
      # @param logo_icon [String] Material Design icon name (required)
      # @param logo_color [String] Hex color for the icon (required, must be from valid colors list)
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Created solution data in requested format
      # @raise [ArgumentError] If required parameters are missing or logo_color is invalid
      # @example Create a new solution
      #   create_solution('My Project', 'folder', '#3A86FF')
      #
      # @example With explicit format
      #   create_solution('My Project', 'folder', '#3A86FF', format: :json)
      def create_solution(name, logo_icon, logo_color, format: :toon)
        validate_required_parameter!('name', name)
        validate_required_parameter!('logo_icon', logo_icon)
        validate_required_parameter!('logo_color', logo_color)

        # Normalize color format (ensure uppercase with #)
        normalized_color = normalize_color(logo_color)

        # Validate color is in allowed list
        unless VALID_SOLUTION_COLORS.include?(normalized_color)
          raise ArgumentError, "Invalid logo_color '#{logo_color}'. Must be one of: #{VALID_SOLUTION_COLORS.join(', ')}"
        end

        body = {
          'name' => name,
          'logo_icon' => logo_icon,
          'logo_color' => normalized_color
        }

        response = api_request(:post, '/solutions/', body)

        # Invalidate solutions cache since we created a new one
        @cache.invalidate_solutions_cache if cache_enabled?

        format_single_response(response, format)
      end

      private

      # Normalizes a color string to uppercase hex format with # prefix.
      #
      # @param color [String] Color in various formats (with/without #, any case)
      # @return [String] Normalized color (uppercase with #)
      def normalize_color(color)
        color = color.to_s.strip
        color = "##{color}" unless color.start_with?('#')
        color.upcase
      end

      public

      # Lists solutions owned by a specific user.
      #
      # Fetches all solutions with permissions data, filters client-side by owner,
      # and returns only essential fields to minimize token usage.
      #
      # @param owner_id [String] User ID of the solution owner
      # @param include_activity_data [Boolean] Include activity/usage metrics (default: false)
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Hash] TOON/plain text string or JSON hash depending on format
      # @raise [ArgumentError] If owner_id is missing
      # @example List solutions by owner (TOON format by default)
      #   list_solutions_by_owner('user_abc')
      #   list_solutions_by_owner('user_abc', include_activity_data: true)
      #
      # @example Explicit format selection
      #   list_solutions_by_owner('user_abc', format: :json)
      def list_solutions_by_owner(owner_id, include_activity_data: false, format: :toon)
        validate_required_parameter!('owner_id', owner_id)

        log_metric("→ Listing solutions owned by user: #{owner_id}")

        # Use cache-first strategy - cache stores full data including permissions
        cached_solutions = with_cache_check('solutions') { @cache.get_cached_solutions }
        if cached_solutions
          solutions_list = cached_solutions
        else
          # Cache miss - fetch and cache all solutions
          response = api_request(:get, '/solutions/')
          solutions_list = extract_items_safely(response)

          # Cache the full response
          if cache_enabled?
            @cache.cache_solutions(solutions_list)
            log_metric("✓ Cached #{solutions_list.size} solutions")
          end
        end

        # Filter solutions where the user is in the owners array
        owned_solutions = solutions_list.select do |solution|
          solution['permissions'] &&
            solution['permissions']['owners'] &&
            solution['permissions']['owners'].include?(owner_id)
        end

        # Extract only essential fields to reduce response size
        filtered_solutions = owned_solutions.map do |solution|
          extract_essential_solution_fields(solution, include_activity_data: include_activity_data)
        end

        format_solutions_output(filtered_solutions, format)
      end

      # Gets the most recent record update timestamp across all tables in a solution.
      #
      # Uses cache-first strategy: populates cache with ALL records for each table,
      # then queries the cache to find the most recent update. This ensures records
      # are available for subsequent queries without additional API calls.
      #
      # @param solution_id [String] Solution identifier
      # @return [String, nil] ISO8601 timestamp of most recent record update, or nil if no records
      # @raise [ArgumentError] If solution_id is missing
      # @example
      #   get_solution_most_recent_record_update('sol_123')
      def get_solution_most_recent_record_update(solution_id)
        validate_required_parameter!('solution_id', solution_id)

        # Get all tables for this solution (use JSON format for internal processing)
        tables_response = list_tables(solution_id: solution_id, format: :json)

        return nil unless tables_response['tables'] && !tables_response['tables'].empty?

        most_recent_update = nil

        tables_response['tables'].each do |table|
          table_id = table['id']

          # Use cache-first strategy: populate cache with ALL records
          # This ensures records are available for subsequent queries
          if cache_enabled?
            ensure_records_cached(table_id)

            # Query the cache for the most recent record
            query = @cache.query(table_id)
                          .order('last_updated', 'DESC')
                          .limit(1)
            results = query.execute

            next if results.empty?

            record = results.first
            # Extract last_updated timestamp - cache stores it as JSON string
            last_updated = record['last_updated']
            record_update = extract_last_updated_timestamp(last_updated)
          else
            # Fallback: direct API call (original behavior when cache disabled)
            base_path = "/applications/#{table_id}/records/list/"
            endpoint = build_endpoint(base_path, limit: 1, offset: 0)
            body = { sort: [{ 'field' => 'last_updated', 'direction' => 'desc' }] }

            records_response = api_request(:post, endpoint, body)

            next unless records_response['items']&.first

            record = records_response['items'].first
            record_update = record.dig('last_updated', 'on')
          end

          most_recent_update = record_update if record_update && (most_recent_update.nil? || record_update > most_recent_update)
        end

        most_recent_update
      end

      private

      # Extract timestamp from last_updated field value.
      #
      # Cache stores last_updated as JSON string with 'on' key.
      # API returns it as Hash with 'on' key.
      #
      # @param last_updated [String, Hash, nil] Last updated field value
      # @return [String, nil] ISO8601 timestamp or nil
      def extract_last_updated_timestamp(last_updated)
        return nil if last_updated.nil?

        # If it's a string, try to parse as JSON
        if last_updated.is_a?(String)
          begin
            parsed = JSON.parse(last_updated)
            return parsed['on'] if parsed.is_a?(Hash)
          rescue JSON::ParserError
            # Not JSON, return as-is if it looks like a timestamp
            return last_updated if last_updated.match?(/^\d{4}-\d{2}-\d{2}/)
          end
        end

        # If it's a Hash, extract 'on' key
        return last_updated['on'] if last_updated.is_a?(Hash)

        nil
      end

      # Extracts essential fields from a solution to reduce response size.
      #
      # @param solution [Hash] Full solution data from API
      # @param include_activity_data [Boolean] Whether to include usage metrics
      # @return [Hash] Solution with only essential fields
      def extract_essential_solution_fields(solution, include_activity_data: false)
        base_fields = {
          'id' => solution['id'],
          'name' => solution['name'],
          'logo_icon' => solution['logo_icon'],
          'logo_color' => solution['logo_color']
        }

        return base_fields unless include_activity_data

        base_fields.merge(
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
        )
      end

      public

      # Analyzes solution usage to identify inactive solutions.
      #
      # Returns solutions categorized by usage level based on configurable thresholds.
      # Useful for identifying candidates for archival or cleanup.
      #
      # @param days_inactive [Integer] Days since last access to consider inactive (default: 90)
      # @param min_records [Integer] Minimum records to not be considered empty (default: 10)
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Solutions categorized by usage in requested format
      # @example
      #   analyze_solution_usage
      #   analyze_solution_usage(days_inactive: 60, min_records: 5, format: :json)
      def analyze_solution_usage(days_inactive: 90, min_records: 10, format: :toon)
        log_metric("→ Analyzing solution usage (inactive: #{days_inactive} days, min_records: #{min_records})")

        # Get all solutions with activity data (use JSON format for internal processing)
        solutions_data = list_solutions(include_activity_data: true, format: :json)
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

        format_single_response(result, format)
      end
    end
  end
end
