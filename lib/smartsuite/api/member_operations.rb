module SmartSuite
  module API
    # MemberOperations handles workspace user and team management.
    #
    # This module provides methods for:
    # - Listing workspace members with optional solution-based filtering
    # - Listing and retrieving teams with caching
    #
    # Implements server-side filtering to reduce token usage when querying
    # solution-specific members.
    module MemberOperations
      # Lists workspace members with optional solution filtering.
      #
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
      # @return [Hash] Members with count and optional filter indication
      def list_members(limit = 100, offset = 0, solution_id: nil)
        if solution_id
          log_metric("→ Listing members for solution: #{solution_id}")

          # Get solution details to find member IDs
          solution = get_solution(solution_id)

          # Extract member IDs from permissions structure
          solution_member_ids = []

          # Add members from permissions.members (array of {access, entity})
          if solution['permissions'] && solution['permissions']['members']
            solution_member_ids += solution['permissions']['members'].map { |m| m['entity'] }
          end

          # Add members from permissions.owners (array of IDs)
          if solution['permissions'] && solution['permissions']['owners']
            solution_member_ids += solution['permissions']['owners']
          end

          # Add members from teams
          if solution['permissions'] && solution['permissions']['teams']
            team_ids = solution['permissions']['teams'].map { |t| t['entity'] }
            log_metric("→ Found #{team_ids.size} team(s), fetching team members...")

            team_ids.each do |team_id|
              begin
                team = get_team(team_id)
                if team && team['members'] && team['members'].is_a?(Array)
                  solution_member_ids += team['members']
                  log_metric("  Team #{team['name'] || team_id}: added #{team['members'].size} member(s)")
                end
              rescue => e
                log_metric("  ⚠️  Failed to fetch team #{team_id}: #{e.message}")
              end
            end
          end

          solution_member_ids.uniq!

          if solution_member_ids.empty?
            log_metric("⚠️  Solution has no members")
            return { 'members' => [], 'count' => 0, 'total_count' => 0, 'filtered_by_solution' => solution_id }
          end

          # Get all members (with high limit to ensure we get all)
          query_params = "?limit=1000&offset=0"

          response = api_request(:post, "/members/list/#{query_params}", nil)

          if response.is_a?(Hash) && response['items'].is_a?(Array)
            # Filter to only members in the solution
            filtered_members = response['items'].select { |member| solution_member_ids.include?(member['id']) }

            members = filtered_members.map do |member|
              result = {
                'id' => member['id'],
                'email' => member['email'],
                'role' => member['role'],
                'status' => member['status']
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

            result = {
              'members' => members,
              'count' => members.size,
              'total_count' => members.size,
              'filtered_by_solution' => solution_id
            }
            tokens = estimate_tokens(JSON.generate(result))
            log_metric("✓ Found #{members.size} members (filtered from #{response['items'].size} total)")
            log_token_usage(tokens)
            result
          else
            response
          end
        else
          log_metric("→ Listing workspace members")

          query_params = "?limit=#{limit}&offset=#{offset}"

          response = api_request(:post, "/members/list/#{query_params}", nil)

          # Extract only essential member information
          if response.is_a?(Hash) && response['items'].is_a?(Array)
            members = response['items'].map do |member|
              result = {
                'id' => member['id'],
                'email' => member['email'],
                'role' => member['role'],
                'status' => member['status']
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

            result = { 'members' => members, 'count' => members.size, 'total_count' => response['total_count'] }
            tokens = estimate_tokens(JSON.generate(result))
            log_metric("✓ Found #{members.size} members")
            log_token_usage(tokens)
            result
          else
            response
          end
        end
      end

      # Lists all teams in the workspace with caching.
      #
      # Teams are cached in memory for efficient lookups. Uses high limit
      # (1000) to fetch all teams in one request.
      #
      # @return [Array<Hash>] Array of team objects
      def list_teams
        log_metric("→ Listing teams")
        query_params = "?limit=1000&offset=0"
        response = api_request(:post, "/teams/list/#{query_params}", nil)

        # Cache teams for efficient lookup
        @teams_cache ||= {}

        # Handle both array response and hash with 'items' key
        teams = response.is_a?(Hash) && response['items'] ? response['items'] : response

        if teams.is_a?(Array)
          teams.each do |team|
            @teams_cache[team['id']] = team
          end
        end

        teams
      end

      # Retrieves a specific team by ID, using cache if available.
      #
      # Checks cached teams first. If not found, fetches all teams and
      # populates the cache.
      #
      # @param team_id [String] Team identifier
      # @return [Hash, nil] Team object or nil if not found
      def get_team(team_id)
        # Use cached teams if available
        if @teams_cache && @teams_cache[team_id]
          log_metric("→ Using cached team: #{team_id}")
          return @teams_cache[team_id]
        end

        # Otherwise, fetch all teams and cache them
        log_metric("→ Fetching team from teams list: #{team_id}")
        list_teams  # This populates @teams_cache
        @teams_cache[team_id]
      end
    end
  end
end
