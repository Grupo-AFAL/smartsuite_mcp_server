# frozen_string_literal: true

require_relative 'base'

module SmartSuite
  module API
    # MemberOperations handles workspace user and team management.
    #
    # This module provides methods for:
    # - Listing workspace members with optional solution-based filtering
    # - Searching members by name or email
    # - Listing and retrieving teams with caching
    #
    # Implements cache-first strategy with SQLite-based caching (7-day TTL).
    # Uses Base module for common API patterns (validation, endpoint building, response tracking).
    module MemberOperations
      include Base

      # Lists workspace members with optional solution filtering.
      #
      # Uses cache-first strategy: checks SQLite cache before making API calls.
      # When solution_id provided, fetches solution permissions, extracts member IDs
      # from direct members, owners, and team memberships, then filters the full
      # member list. This server-side filtering saves significant tokens.
      #
      # Returns filtered member data with only essential fields (id, email, role,
      # status, name, job_title, department).
      #
      # @param limit [Integer] Maximum members to return (default: 100, ignored with solution_id)
      # @param offset [Integer] Pagination offset (default: 0, ignored with solution_id)
      # @param solution_id [String, nil] Optional solution ID to filter members
      # @param include_inactive [Boolean] Include deactivated members (default: false)
      # @return [Hash] Members with count and optional filter indication
      # @example List all members
      #   list_members(limit: 100, offset: 0)
      #
      # @example List members by solution
      #   list_members(solution_id: 'sol_123')
      #
      # @example Include deactivated members
      #   list_members(include_inactive: true)
      def list_members(limit: Base::Pagination::DEFAULT_LIMIT, offset: Base::Pagination::DEFAULT_OFFSET,
                       solution_id: nil, include_inactive: false)
        if solution_id
          list_members_by_solution(solution_id, include_inactive: include_inactive)
        else
          list_all_members(limit, offset, include_inactive: include_inactive)
        end
      end

      # Searches for members by name or email.
      #
      # Uses cache-first strategy with fuzzy matching support.
      # Searches in: email, first_name, last_name, full_name.
      #
      # @param query [String] Search query for name or email
      # @param include_inactive [Boolean] Include deactivated members (default: false)
      # @return [Hash] Matching members with count
      # @raise [ArgumentError] If query is missing
      # @example
      #   search_member('john@example.com')
      #   search_member('Smith')
      #   search_member('John', include_inactive: true)
      def search_member(query, include_inactive: false)
        validate_required_parameter!('query', query)

        log_metric("→ Searching members with query: #{query}")

        # Try cache first with query filtering
        unless should_bypass_cache?
          cached_members = @cache.get_cached_members(query: query, include_inactive: include_inactive)
          if cached_members
            log_cache_hit('members', cached_members.size, "query:#{query}")
            sorted_members = sort_members_by_match_score(cached_members, query)
            result = build_collection_response(sorted_members, :members, query: query)
            return track_response_size(result, "Found #{sorted_members.size} matching members (cached)")
          else
            log_cache_miss('members', "query:#{query}")
          end
        end

        # Fetch all members from API
        all_members = fetch_all_members_from_api

        return all_members unless all_members.is_a?(Array)

        # Filter by status unless include_inactive (status 1 or 'active' = active, nil = treat as active)
        filtered_members = if include_inactive
                             all_members
                           else
                             all_members.select { |m| member_active?(m) }
                           end

        # Filter members by query using fuzzy matching (consistent with cache path)
        matching_members = filtered_members.select do |member|
          match_member_formatted?(member, query)
        end

        # Sort by match score (best matches first)
        sorted_members = sort_members_by_match_score(matching_members, query)

        result = build_collection_response(sorted_members, :members, query: query)
        track_response_size(result, "Found #{sorted_members.size} matching members")
      end

      # Lists all teams in the workspace with caching.
      #
      # Uses cache-first strategy: checks SQLite cache before making API calls.
      # Teams are cached for 7 days by default.
      #
      # @return [Array<Hash>] Array of team objects
      # @example
      #   list_teams
      def list_teams
        log_metric('→ Listing teams')
        teams = fetch_teams_with_cache
        format_team_list(teams)
      end

      # Retrieves a specific team by ID, using cache if available.
      # Returns team data with enriched member details (name, email, etc.)
      # instead of just member IDs.
      #
      # Checks SQLite cache first. If not found, fetches all teams and
      # populates the cache.
      #
      # @param team_id [String] Team identifier
      # @return [Hash, nil] Team object with enriched members or nil if not found
      # @raise [ArgumentError] If team_id is missing
      # @example
      #   get_team('team_abc')
      def get_team(team_id)
        validate_required_parameter!('team_id', team_id)

        team = fetch_team_by_id(team_id)
        return nil unless team

        enrich_team_with_members(team)
      end

      private

      # Lists all workspace members with cache-first strategy.
      #
      # @param limit [Integer] Maximum members to return
      # @param offset [Integer] Pagination offset
      # @param include_inactive [Boolean] Include deactivated members
      # @return [Hash] Members response with count
      def list_all_members(limit, offset, include_inactive: false)
        log_metric('→ Listing workspace members')

        # Try cache first if enabled
        unless should_bypass_cache?
          cached_members = @cache.get_cached_members(include_inactive: include_inactive)
          if cached_members
            log_cache_hit('members', cached_members.size)
            # Apply pagination to cached results
            paginated = cached_members[offset, limit] || []
            result = build_collection_response(paginated, :members, total_count: cached_members.size)
            return track_response_size(result, "Found #{paginated.size} members (cached, #{cached_members.size} total)")
          else
            log_cache_miss('members')
          end
        end

        # Fetch all members from API and cache them
        all_members = fetch_all_members_from_api

        return all_members unless all_members.is_a?(Array)

        # Filter by status unless include_inactive (status 1 or 'active' = active, nil = treat as active)
        filtered_members = if include_inactive
                             all_members
                           else
                             all_members.select { |m| member_active?(m) }
                           end

        # Apply pagination
        paginated = filtered_members[offset, limit] || []
        result = build_collection_response(paginated, :members, total_count: filtered_members.size)
        track_response_size(result, "Found #{paginated.size} members (#{filtered_members.size} total)")
      end

      # Lists members filtered by solution.
      #
      # @param solution_id [String] Solution ID to filter members
      # @param include_inactive [Boolean] Include deactivated members
      # @return [Hash] Filtered members response
      def list_members_by_solution(solution_id, include_inactive: false)
        log_metric("→ Listing members for solution: #{solution_id}")

        solution_member_ids = fetch_solution_member_ids(solution_id)

        if solution_member_ids.empty?
          log_metric('⚠️  Solution has no members')
          return build_collection_response([], :members, total_count: 0, filtered_by_solution: solution_id)
        end

        # Try cache first if enabled
        all_members = nil
        unless should_bypass_cache?
          cached_members = @cache.get_cached_members(include_inactive: include_inactive)
          if cached_members
            log_cache_hit('members', cached_members.size)
            all_members = cached_members
          else
            log_cache_miss('members')
          end
        end

        # Fetch from API if not cached
        if all_members.nil?
          all_members = fetch_all_members_from_api
          return all_members unless all_members.is_a?(Array)

          # Filter by status unless include_inactive (status 1 or 'active' = active, nil = treat as active)
          all_members = all_members.select { |m| member_active?(m) } unless include_inactive
        end

        # Filter to only members in the solution
        filtered_members = all_members.select { |member| solution_member_ids.include?(member['id']) }

        result = build_collection_response(filtered_members, :members,
                                           total_count: filtered_members.size,
                                           filtered_by_solution: solution_id)
        track_response_size(result, "Found #{filtered_members.size} members (filtered from #{all_members.size} total)")
      end

      # Fetches all members from API and caches them.
      #
      # @return [Array<Hash>, Hash] Formatted members array or error response
      def fetch_all_members_from_api
        endpoint = build_endpoint('/members/list/',
                                  limit: Base::Pagination::FETCH_ALL_LIMIT,
                                  offset: 0)

        response = api_request(:post, endpoint, nil)

        if response.is_a?(Hash) && response['items'].is_a?(Array)
          members = format_member_list(response['items'])

          # Cache the formatted members if cache enabled
          if cache_enabled?
            @cache.cache_members(members)
            log_metric("✓ Cached #{members.size} members")
          end

          members
        else
          response
        end
      end

      # Fetches all teams with cache-first strategy.
      # Returns full team data including member IDs array.
      #
      # @return [Array<Hash>] Array of team objects with full data
      def fetch_teams_with_cache
        # Try cache first if enabled
        unless should_bypass_cache?
          cached_teams = @cache.get_cached_teams
          if cached_teams
            log_cache_hit('teams', cached_teams.size)
            return cached_teams
          else
            log_cache_miss('teams')
          end
        end

        # Fetch from API
        endpoint = build_endpoint('/teams/list/',
                                  limit: Base::Pagination::FETCH_ALL_LIMIT,
                                  offset: 0)
        response = api_request(:post, endpoint, nil)

        # Handle both array response and hash with 'items' key
        teams = response.is_a?(Hash) && response['items'] ? response['items'] : response

        # Cache teams if cache enabled
        if teams.is_a?(Array) && cache_enabled?
          @cache.cache_teams(teams)
          log_metric("✓ Cached #{teams.size} teams")
        end

        teams
      end

      # Fetches a team by ID from cache or API (raw data, not enriched).
      # Used internally for permission lookups.
      #
      # @param team_id [String] Team identifier
      # @return [Hash, nil] Raw team object or nil if not found
      def fetch_team_by_id(team_id)
        # Try to get specific team from cache first
        unless should_bypass_cache?
          cached_team = @cache.get_cached_team(team_id)
          if cached_team
            log_cache_hit('team', team_id)
            return cached_team
          end
        end

        # Fetch all teams (which will cache them) and find the specific one
        log_metric("→ Fetching team from teams list: #{team_id}")
        teams = fetch_teams_with_cache
        teams&.find { |t| t['id'] == team_id }
      end

      # Enriches a team with member details instead of just IDs.
      #
      # @param team [Hash] Team object with member IDs array
      # @return [Hash] Team with enriched member details
      def enrich_team_with_members(team)
        return team unless team['members'].is_a?(Array)

        member_ids = team['members']

        # Get all members from cache
        all_members = @cache.get_cached_members(include_inactive: true) || []

        # Build a lookup hash for quick access
        members_by_id = all_members.each_with_object({}) { |m, h| h[m['id']] = m }

        # Enrich member IDs with details
        enriched_members = member_ids.map do |member_id|
          member = members_by_id[member_id]
          if member
            {
              'id' => member['id'],
              'email' => member['email'],
              'full_name' => member['full_name'],
              'first_name' => member['first_name'],
              'last_name' => member['last_name']
            }.compact
          else
            { 'id' => member_id }
          end
        end

        {
          'id' => team['id'],
          'name' => team['name'],
          'description' => team['description'],
          'member_count' => member_ids.size,
          'members' => enriched_members
        }
      end

      # Fetches solution details and extracts unique member IDs from permissions.
      # Includes direct members, owners, and members of assigned teams.
      #
      # @param solution_id [String] Solution identifier
      # @return [Array<String>] Array of unique member IDs
      def fetch_solution_member_ids(solution_id)
        # Get solution details to find member IDs
        solution = get_solution(solution_id)
        return [] unless solution['permissions']

        member_ids = []

        # Add members from permissions.members (array of {access, entity})
        member_ids += solution['permissions']['members'].map { |m| m['entity'] } if solution['permissions']['members']

        # Add members from permissions.owners (array of IDs)
        member_ids += solution['permissions']['owners'] if solution['permissions']['owners']

        # Add members from teams
        if solution['permissions']['teams']
          team_ids = solution['permissions']['teams'].map { |t| t['entity'] }
          log_metric("→ Found #{team_ids.size} team(s), fetching team members...")

          team_ids.each do |team_id|
            team = fetch_team_by_id(team_id)
            if team && team['members'].is_a?(Array)
              member_ids += team['members']
              log_metric("  Team #{team['name'] || team_id}: added #{team['members'].size} member(s)")
            end
          rescue StandardError => e
            log_metric("  ⚠️  Failed to fetch team #{team_id}: #{e.message}")
          end
        end

        member_ids.uniq
      end

      # Formats a list of raw member objects into essential fields.
      #
      # @param items [Array<Hash>] Raw member objects from API
      # @return [Array<Hash>] Formatted member objects
      def format_member_list(items)
        items.map do |member|
          # Handle email - can be string or array
          email = member['email'].is_a?(Array) ? member['email'].first : member['email']

          # Handle status - API returns hash {"value": "1", "updated_on": "..."} or plain value
          status = member['status'].is_a?(Hash) ? member['status']['value'] : member['status']

          # Handle deleted_date - API returns {"date": "2024-..." or null}
          deleted_date = member['deleted_date'] && member['deleted_date']['date']

          result = {
            'id' => member['id'],
            'email' => email,
            'role' => member['role'],
            'status' => status,
            'deleted_date' => deleted_date
          }

          # Add name fields if available
          if member['full_name']
            result['first_name'] = member['full_name']['first_name']
            result['last_name'] = member['full_name']['last_name']
            result['full_name'] = member['full_name']['sys_root']
          end

          # Add other useful fields
          result['job_title'] = member['job_title'] if member['job_title']
          result['department'] = member['department'] if member['department']

          result.compact # Remove nil values
        end
      end

      # Checks if a raw member object matches the search query.
      # Matches against email, first name, last name, and full name.
      #
      # @param member [Hash] Raw member object from API
      # @param query_lower [String] Lowercase search query
      # @return [Boolean] True if member matches query
      def match_member?(member, query_lower)
        # Search in email (handle both string and array)
        email_match = false
        if member['email']
          email = member['email'].is_a?(Array) ? member['email'].first : member['email']
          email_match = email && email.to_s.downcase.include?(query_lower)
        end

        # Search in name fields
        name_match = false
        if member['full_name']
          first_name = member['full_name']['first_name'].to_s
          last_name = member['full_name']['last_name'].to_s
          full_name = member['full_name']['sys_root'].to_s

          name_match = first_name.downcase.include?(query_lower) ||
                       last_name.downcase.include?(query_lower) ||
                       full_name.downcase.include?(query_lower)
        end

        email_match || name_match
      end

      # Sorts members by match score (best matches first).
      #
      # @param members [Array<Hash>] Array of member objects
      # @param query [String] The search query
      # @return [Array<Hash>] Sorted members (best match first)
      def sort_members_by_match_score(members, query)
        members.sort_by do |member|
          # Calculate score based on multiple fields, take the best
          scores = []

          # Check full_name
          scores << FuzzyMatcher.match_score(member['full_name'].to_s, query) if member['full_name']

          # Check first_name
          scores << FuzzyMatcher.match_score(member['first_name'].to_s, query) if member['first_name']

          # Check last_name
          scores << FuzzyMatcher.match_score(member['last_name'].to_s, query) if member['last_name']

          # Check email (but weight it slightly lower)
          scores << (FuzzyMatcher.match_score(member['email'].to_s, query) * 0.9) if member['email']

          # Return negative for descending sort (highest score first)
          -(scores.max || 0)
        end
      end

      # Checks if a formatted member object matches the search query.
      # Uses FuzzyMatcher for consistency with cached search (typo tolerance).
      #
      # @param member [Hash] Formatted member object
      # @param query [String] Search query (case-insensitive, fuzzy matched)
      # @return [Boolean] True if member matches query
      def match_member_formatted?(member, query)
        # Search in email (substring match for email - no fuzzy for technical strings)
        email = member['email']
        email_match = email && email.to_s.downcase.include?(query.downcase)

        # Search in name fields using FuzzyMatcher for consistency with cache path
        first_name = member['first_name']
        last_name = member['last_name']
        full_name = member['full_name']

        name_match = FuzzyMatcher.match?(full_name.to_s, query) ||
                     FuzzyMatcher.match?(first_name.to_s, query) ||
                     FuzzyMatcher.match?(last_name.to_s, query)

        email_match || name_match
      end

      # Checks if a member is considered active (not soft-deleted).
      # Members with deleted_date set are soft-deleted and hidden from UI.
      # Status values: 1 = active, 4 = invited (pending), 2 = unknown
      #
      # @param member [Hash] Member object (formatted, with deleted_date field)
      # @return [Boolean] True if member is not deleted
      def member_active?(member)
        # Check deleted_date - if set, member is soft-deleted
        deleted_date = member['deleted_date']
        deleted_date.nil? || (deleted_date.respond_to?(:empty?) && deleted_date.empty?)
      end

      # Formats team list for API response.
      # Replaces members array with member_count to reduce token usage.
      #
      # @param teams [Array<Hash>] Array of team objects from API/cache
      # @return [Array<Hash>] Formatted teams with member_count instead of members
      def format_team_list(teams)
        return teams unless teams.is_a?(Array)

        teams.map do |team|
          members = team['members']
          member_count = members.is_a?(Array) ? members.size : (members || 0)

          {
            'id' => team['id'],
            'name' => team['name'],
            'description' => team['description'],
            'member_count' => member_count
          }
        end
      end
    end
  end
end
