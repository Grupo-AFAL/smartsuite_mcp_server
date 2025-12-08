# frozen_string_literal: true

require_relative "../../../lib/smart_suite/logger"

module Cache
  # PostgreSQL-based cache layer for the hosted SmartSuite MCP server.
  #
  # This is a simplified JSONB-based cache that implements the same interface
  # as SmartSuite::Cache::Layer but uses PostgreSQL instead of SQLite.
  #
  # Key differences from SQLite version:
  # - Uses single table with JSONB instead of dynamic tables per SmartSuite table
  # - Uses ActiveRecord connection instead of raw SQLite
  # - Simpler schema - stores entire records as JSONB
  # - Shared across all users (multi-tenant cache)
  class PostgresLayer
    # Default TTL values in seconds
    DEFAULT_TTL = 12 * 3600 # 12 hours for records
    METADATA_TTL = 7 * 24 * 3600 # 7 days for solutions, tables, members

    # Thread-local storage for tracking cache hits/misses per request
    def self.request_cache_status
      Thread.current[:smartsuite_cache_status] ||= { hits: 0, misses: 0 }
    end

    def self.reset_request_cache_status!
      Thread.current[:smartsuite_cache_status] = { hits: 0, misses: 0 }
    end

    def self.record_hit!
      request_cache_status[:hits] += 1
    end

    def self.record_miss!
      request_cache_status[:misses] += 1
    end

    def self.cache_hit_for_request?
      status = request_cache_status
      status[:hits] > 0 && status[:misses] == 0
    end

    def initialize
      @perf_counters = Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } }
      @just_cached = {} # Track tables that were just cached to avoid duplicate logging
    end

    # ========== Record Caching ==========

    # Cache all records from a SmartSuite table
    def cache_table_records(table_id, structure, records, ttl: nil)
      ttl_seconds = ttl || DEFAULT_TTL
      now = Time.current
      expires_at = now + ttl_seconds

      # Cache the table structure
      cache_table_schema(table_id, structure, ttl: METADATA_TTL)

      # Also cache in cache_tables for solution_id lookup
      cache_single_table(structure, ttl: METADATA_TTL) if structure

      # Delete existing records for this table
      execute_sql("DELETE FROM cache_records WHERE table_id = $1", [ table_id ])

      # Bulk insert records
      records.each do |record|
        execute_sql(
          "INSERT INTO cache_records (table_id, record_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)",
          [ table_id, record["id"], record.to_json, now, expires_at ]
        )
      end

      # Log the cache population (single log entry for the whole operation)
      table_info = get_table_info_for_logging(table_id)
      SmartSuite::Logger.cache("CACHED", table_id, table_info.merge(records: records.size))

      # Mark as just cached to avoid duplicate HIT log on immediate read
      @just_cached[table_id] = true

      records.size
    end

    # Check if cached records are valid (not expired)
    def cache_valid?(table_id)
      result = execute_sql(
        "SELECT COUNT(*) as count FROM cache_records WHERE table_id = $1 AND expires_at > $2",
        [ table_id, Time.current ]
      ).first

      result && result["count"].to_i.positive?
    end

    # Get cached records with filtering and pagination
    def get_cached_records(table_id, filter: nil, sort: nil, limit: nil, offset: nil, fields: nil)
      return nil unless cache_valid?(table_id)

      # Build query
      sql = "SELECT data FROM cache_records WHERE table_id = $1 AND expires_at > $2"
      params = [ table_id, Time.current ]

      # Apply JSONB filters if provided
      if filter
        filter_sql, filter_params = build_jsonb_filter(filter, params.size)
        sql += " AND #{filter_sql}" if filter_sql
        params.concat(filter_params)
      end

      # Apply sorting
      if sort && sort.is_a?(Array) && sort.any?
        sort_clauses = sort.map do |s|
          field = s["field"] || s[:field]
          direction = (s["direction"] || s[:direction] || "asc").upcase
          direction = "ASC" unless %w[ASC DESC].include?(direction)
          "data->>'#{sanitize_field_name(field)}' #{direction}"
        end
        sql += " ORDER BY #{sort_clauses.join(', ')}"
      end

      # Apply limit and offset
      if limit
        sql += " LIMIT $#{params.size + 1}"
        params << limit.to_i
      end

      if offset
        sql += " OFFSET $#{params.size + 1}"
        params << offset.to_i
      end

      results = execute_sql(sql, params)
      return nil if results.empty?

      # Log cache hit only if not immediately after caching (avoid duplicate logs)
      if @just_cached.delete(table_id)
        # Skip logging - we just logged CACHED for this table
      else
        table_info = get_table_info_for_logging(table_id)
        SmartSuite::Logger.cache("HIT", table_id, table_info.merge(records: results.size))
      end
      self.class.record_hit!

      # Parse JSONB and filter fields
      records = results.map { |row| JSON.parse(row["data"]) }

      # Filter to requested fields if specified
      if fields && fields.any?
        records = records.map do |record|
          fields.each_with_object({ "id" => record["id"] }) do |field, h|
            h[field] = record[field] if record.key?(field)
          end
        end
      end

      records
    end

    # Get total count of records for a table (respecting filters)
    def get_cached_record_count(table_id, filter: nil)
      return 0 unless cache_valid?(table_id)

      sql = "SELECT COUNT(*) as count FROM cache_records WHERE table_id = $1 AND expires_at > $2"
      params = [ table_id, Time.current ]

      if filter
        filter_sql, filter_params = build_jsonb_filter(filter, params.size)
        sql += " AND #{filter_sql}" if filter_sql
        params.concat(filter_params)
      end

      result = execute_sql(sql, params).first
      result ? result["count"].to_i : 0
    end

    # Cache or update a single record (used after create/update operations)
    def cache_single_record(table_id, record)
      return false unless record && record["id"]

      now = Time.current
      expires_at = now + DEFAULT_TTL

      # Upsert the record
      execute_sql(
        'INSERT INTO cache_records (table_id, record_id, data, cached_at, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (table_id, record_id)
         DO UPDATE SET data = $3, cached_at = $4, expires_at = $5',
        [ table_id, record["id"], record.to_json, now, expires_at ]
      )

      true
    end

    # Delete a single cached record
    def delete_cached_record(table_id, record_id)
      execute_sql(
        "DELETE FROM cache_records WHERE table_id = $1 AND record_id = $2",
        [ table_id, record_id ]
      )
      true
    end

    # Get a single cached record
    def get_cached_record(table_id, record_id)
      return nil unless cache_valid?(table_id)

      result = execute_sql(
        "SELECT data FROM cache_records WHERE table_id = $1 AND record_id = $2 AND expires_at > $3",
        [ table_id, record_id, Time.current ]
      ).first

      return nil unless result

      # Log cache hit with table info
      table_info = get_table_info_for_logging(table_id)
      SmartSuite::Logger.cache("HIT", table_id, table_info.merge(record_id: record_id))
      self.class.record_hit!

      JSON.parse(result["data"])
    end

    # Invalidate cache for a table
    def invalidate_table_cache(table_id, structure_changed: true)
      execute_sql("DELETE FROM cache_records WHERE table_id = $1", [ table_id ])

      return unless structure_changed

      execute_sql("DELETE FROM cache_table_schemas WHERE table_id = $1", [ table_id ])
    end

    # ========== Solution Caching ==========

    def cache_solutions(solutions, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl

      execute_sql("DELETE FROM cache_solutions")

      solutions.each do |solution|
        execute_sql(
          "INSERT INTO cache_solutions (solution_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4)",
          [ solution["id"], solution.to_json, now, expires_at ]
        )
      end

      solutions.size
    end

    def get_cached_solutions(name: nil)
      unless solutions_cache_valid?
        SmartSuite::Logger.cache("MISS", "solutions")
        self.class.record_miss!
        return nil
      end

      sql = "SELECT data FROM cache_solutions WHERE expires_at > $1"
      params = [ Time.current ]

      if name
        # Use ILIKE for case-insensitive search (replaces fuzzy_match function)
        sql += " AND data->>'name' ILIKE $2"
        params << "%#{name}%"
      end

      results = execute_sql(sql, params)
      if results.empty?
        SmartSuite::Logger.cache("MISS", "solutions", count: 0)
        self.class.record_miss!
        return nil
      end

      SmartSuite::Logger.cache("HIT", "solutions", count: results.size)
      self.class.record_hit!
      results.map { |row| JSON.parse(row["data"]) }
    end

    def solutions_cache_valid?
      result = execute_sql(
        "SELECT COUNT(*) as count FROM cache_solutions WHERE expires_at > $1",
        [ Time.current ]
      ).first

      result && result["count"].to_i.positive?
    end

    def invalidate_solutions_cache
      execute_sql("DELETE FROM cache_solutions")
      invalidate_table_list_cache(nil)
    end

    # ========== Table List Caching ==========

    def cache_table_list(solution_id, tables, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl

      if solution_id
        execute_sql("DELETE FROM cache_tables WHERE solution_id = $1", [ solution_id ])
      else
        execute_sql("DELETE FROM cache_tables")
      end

      tables.each do |table|
        sol_id = table["solution"] || table["solution_id"] || solution_id
        execute_sql(
          'INSERT INTO cache_tables (table_id, solution_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (table_id) DO UPDATE SET solution_id = $2, data = $3, cached_at = $4, expires_at = $5',
          [ table["id"], sol_id, table.to_json, now, expires_at ]
        )
      end

      tables.size
    end

    def cache_single_table(table, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl
      sol_id = table["solution"] || table["solution_id"]

      execute_sql(
        'INSERT INTO cache_tables (table_id, solution_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (table_id) DO UPDATE SET solution_id = $2, data = $3, cached_at = $4, expires_at = $5',
        [ table["id"], sol_id, table.to_json, now, expires_at ]
      )

      true
    end

    def get_cached_table_list(solution_id)
      cache_key = solution_id || "all"
      unless table_list_cache_valid?(solution_id)
        SmartSuite::Logger.cache("MISS", "tables:#{cache_key}")
        self.class.record_miss!
        return nil
      end

      sql = "SELECT data FROM cache_tables WHERE expires_at > $1"
      params = [ Time.current ]

      if solution_id
        sql += " AND solution_id = $2"
        params << solution_id
      end

      results = execute_sql(sql, params)
      if results.empty?
        SmartSuite::Logger.cache("MISS", "tables:#{cache_key}", count: 0)
        self.class.record_miss!
        return nil
      end

      SmartSuite::Logger.cache("HIT", "tables:#{cache_key}", count: results.size)
      self.class.record_hit!
      results.map { |row| JSON.parse(row["data"]) }
    end

    def get_cached_table(table_id)
      result = execute_sql(
        "SELECT data FROM cache_tables WHERE table_id = $1 AND expires_at > $2",
        [ table_id, Time.current ]
      ).first

      # No logging for table structure lookups - they're internal operations
      return nil unless result

      JSON.parse(result["data"])
    end

    def table_list_cache_valid?(solution_id)
      sql = "SELECT COUNT(*) as count FROM cache_tables WHERE expires_at > $1"
      params = [ Time.current ]

      if solution_id
        sql += " AND solution_id = $2"
        params << solution_id
      end

      result = execute_sql(sql, params).first
      result && result["count"].to_i.positive?
    end

    def invalidate_table_list_cache(solution_id)
      if solution_id
        # Get table IDs for this solution
        table_ids = execute_sql(
          "SELECT table_id FROM cache_tables WHERE solution_id = $1",
          [ solution_id ]
        ).map { |r| r["table_id"] }

        # Invalidate records for these tables
        table_ids.each { |tid| invalidate_table_cache(tid, structure_changed: false) }

        execute_sql("DELETE FROM cache_tables WHERE solution_id = $1", [ solution_id ])
      else
        execute_sql("DELETE FROM cache_records")
        execute_sql("DELETE FROM cache_tables")
      end
    end

    # ========== Member Caching ==========

    def cache_members(members, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl

      execute_sql("DELETE FROM cache_members")

      members.each do |member|
        execute_sql(
          "INSERT INTO cache_members (member_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4)",
          [ member["id"], member.to_json, now, expires_at ]
        )
      end

      members.size
    end

    def get_cached_members(query: nil, include_inactive: false)
      unless members_cache_valid?
        SmartSuite::Logger.cache("MISS", "members")
        self.class.record_miss!
        return nil
      end

      sql = "SELECT data FROM cache_members WHERE expires_at > $1"
      params = [ Time.current ]

      unless include_inactive
        sql += " AND (data->>'deleted_date' IS NULL OR data->>'deleted_date' = '')"
      end

      if query
        # Use ILIKE for case-insensitive search on full_name, first_name, last_name, and email
        # This replaces SQLite's fuzzy_match function
        sql += " AND (data->>'full_name' ILIKE $#{params.size + 1}" \
               " OR data->>'first_name' ILIKE $#{params.size + 1}" \
               " OR data->>'last_name' ILIKE $#{params.size + 1}" \
               " OR data->>'email' ILIKE $#{params.size + 1})"
        params << "%#{query}%"
      end

      results = execute_sql(sql, params)
      if results.empty?
        SmartSuite::Logger.cache("MISS", "members", count: 0)
        self.class.record_miss!
        return nil
      end

      SmartSuite::Logger.cache("HIT", "members", count: results.size)
      self.class.record_hit!
      results.map { |row| JSON.parse(row["data"]) }
    end

    def members_cache_valid?
      result = execute_sql(
        "SELECT COUNT(*) as count FROM cache_members WHERE expires_at > $1",
        [ Time.current ]
      ).first

      result && result["count"].to_i.positive?
    end

    def invalidate_members_cache
      execute_sql("DELETE FROM cache_members")
    end

    # ========== Team Caching ==========

    def cache_teams(teams, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl

      execute_sql("DELETE FROM cache_teams")

      teams.each do |team|
        execute_sql(
          "INSERT INTO cache_teams (team_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4)",
          [ team["id"], team.to_json, now, expires_at ]
        )
      end

      teams.size
    end

    def get_cached_teams
      unless teams_cache_valid?
        SmartSuite::Logger.cache("MISS", "teams")
        self.class.record_miss!
        return nil
      end

      results = execute_sql(
        "SELECT data FROM cache_teams WHERE expires_at > $1",
        [ Time.current ]
      )

      if results.empty?
        SmartSuite::Logger.cache("MISS", "teams", count: 0)
        self.class.record_miss!
        return nil
      end

      SmartSuite::Logger.cache("HIT", "teams", count: results.size)
      self.class.record_hit!
      results.map { |row| JSON.parse(row["data"]) }
    end

    def get_cached_team(team_id)
      return nil unless teams_cache_valid?

      result = execute_sql(
        "SELECT data FROM cache_teams WHERE team_id = $1 AND expires_at > $2",
        [ team_id, Time.current ]
      ).first

      return nil unless result

      JSON.parse(result["data"])
    end

    def teams_cache_valid?
      result = execute_sql(
        "SELECT COUNT(*) as count FROM cache_teams WHERE expires_at > $1",
        [ Time.current ]
      ).first

      result && result["count"].to_i.positive?
    end

    def invalidate_teams_cache
      execute_sql("DELETE FROM cache_teams")
    end

    # ========== Deleted Records Caching ==========

    def cache_deleted_records(solution_id, records, ttl: DEFAULT_TTL)
      now = Time.current
      expires_at = now + ttl

      # Create table if not exists
      execute_sql(<<~SQL)
        CREATE TABLE IF NOT EXISTS cache_deleted_records (
          solution_id VARCHAR NOT NULL,
          data JSONB NOT NULL,
          cached_at TIMESTAMP NOT NULL,
          expires_at TIMESTAMP NOT NULL,
          PRIMARY KEY (solution_id)
        )
      SQL

      execute_sql(
        'INSERT INTO cache_deleted_records (solution_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4)
         ON CONFLICT (solution_id) DO UPDATE SET data = $2, cached_at = $3, expires_at = $4',
        [ solution_id, records.to_json, now, expires_at ]
      )

      records.size
    end

    def get_cached_deleted_records(solution_id, full_data: false)
      # Check if table exists
      table_exists = execute_sql(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'cache_deleted_records')"
      ).first&.fetch("exists", false)

      return nil unless table_exists

      result = execute_sql(
        "SELECT data FROM cache_deleted_records WHERE solution_id = $1 AND expires_at > $2",
        [ solution_id, Time.current ]
      ).first

      return nil unless result

      records = JSON.parse(result["data"])

      # If not full_data, return simplified version
      unless full_data
        records = records.map do |r|
          {
            "id" => r["id"],
            "title" => r["title"],
            "deleted_date" => r["deleted_date"],
            "application" => r["application"]
          }
        end
      end

      self.class.record_hit!
      records
    end

    # ========== Table Schema Caching ==========

    def cache_table_schema(table_id, structure, ttl: METADATA_TTL)
      now = Time.current
      expires_at = now + ttl

      execute_sql(
        'INSERT INTO cache_table_schemas (table_id, structure, cached_at, expires_at) VALUES ($1, $2, $3, $4)
         ON CONFLICT (table_id) DO UPDATE SET structure = $2, cached_at = $3, expires_at = $4',
        [ table_id, structure.to_json, now, expires_at ]
      )
    end

    def get_cached_table_schema(table_id)
      result = execute_sql(
        "SELECT structure FROM cache_table_schemas WHERE table_id = $1 AND expires_at > $2",
        [ table_id, Time.current ]
      ).first

      return nil unless result

      JSON.parse(result["structure"])
    end

    # ========== Cache Status & Management ==========

    def get_cache_status(table_id: nil)
      now = Time.current

      status = {
        "timestamp" => now.iso8601,
        "solutions" => get_cache_count_status("cache_solutions", now),
        "tables" => get_cache_count_status("cache_tables", now),
        "members" => get_cache_count_status("cache_members", now),
        "teams" => get_cache_count_status("cache_teams", now),
        "records" => get_records_cache_status(now, table_id: table_id)
      }

      status
    end

    def refresh_cache(resource, table_id: nil, solution_id: nil)
      case resource
      when "solutions"
        invalidate_solutions_cache
        { success: true, message: "Solutions cache invalidated" }
      when "tables"
        invalidate_table_list_cache(solution_id)
        { success: true, message: "Tables cache invalidated#{solution_id ? " for solution #{solution_id}" : ''}" }
      when "records"
        raise ArgumentError, "table_id required for records refresh" unless table_id

        invalidate_table_cache(table_id, structure_changed: false)
        { success: true, message: "Records cache invalidated for table #{table_id}" }
      when "members"
        invalidate_members_cache
        { success: true, message: "Members cache invalidated" }
      when "teams"
        invalidate_teams_cache
        { success: true, message: "Teams cache invalidated" }
      else
        raise ArgumentError, "Unknown resource: #{resource}"
      end
    end

    # Query builder compatibility (simplified)
    def query(table_id)
      PostgresQuery.new(self, table_id)
    end

    private

    def execute_sql(sql, params = [])
      # Use raw connection for PostgreSQL-style $1, $2 parameters
      conn = ActiveRecord::Base.connection.raw_connection
      result = conn.exec_params(sql, params)
      result.to_a
    end

    def sanitize_field_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    def build_jsonb_filter(filter, param_offset)
      return [ nil, [] ] unless filter.is_a?(Hash)

      operator = filter["operator"] || "and"
      fields = filter["fields"] || []

      return [ nil, [] ] if fields.empty?

      conditions = []
      params = []

      fields.each do |field_filter|
        field = field_filter["field"]
        comparison = field_filter["comparison"]
        value = field_filter["value"]

        next unless field && comparison

        param_num = param_offset + params.size + 1
        condition, new_params = build_single_jsonb_condition(field, comparison, value, param_num)

        if condition
          conditions << condition
          params.concat(new_params)
        end
      end

      return [ nil, [] ] if conditions.empty?

      joiner = operator == "or" ? " OR " : " AND "
      [ "(#{conditions.join(joiner)})", params ]
    end

    def build_single_jsonb_condition(field, comparison, value, param_num)
      field_accessor = "data->>'#{sanitize_field_name(field)}'"

      case comparison
      when "is"
        [ "#{field_accessor} = $#{param_num}", [ value.to_s ] ]
      when "is_not"
        [ "#{field_accessor} != $#{param_num}", [ value.to_s ] ]
      when "contains"
        [ "#{field_accessor} ILIKE $#{param_num}", [ "%#{value}%" ] ]
      when "is_greater_than"
        [ "(#{field_accessor})::numeric > $#{param_num}", [ value.to_f ] ]
      when "is_less_than"
        [ "(#{field_accessor})::numeric < $#{param_num}", [ value.to_f ] ]
      when "is_equal_or_greater_than"
        [ "(#{field_accessor})::numeric >= $#{param_num}", [ value.to_f ] ]
      when "is_equal_or_less_than"
        [ "(#{field_accessor})::numeric <= $#{param_num}", [ value.to_f ] ]
      when "is_empty"
        [ "(#{field_accessor} IS NULL OR #{field_accessor} = '')", [] ]
      when "is_not_empty"
        [ "(#{field_accessor} IS NOT NULL AND #{field_accessor} != '')", [] ]
      when "has_any_of"
        if value.is_a?(Array) && value.any?
          # For JSON arrays, check if any value is present
          or_conditions = value.map.with_index do |v, i|
            "data->'#{sanitize_field_name(field)}' @> $#{param_num + i}::jsonb"
          end
          [ "(#{or_conditions.join(' OR ')})", value.map { |v| "[\"#{v}\"]" } ]
        else
          [ nil, [] ]
        end
      when "is_before"
        date_value = extract_date_value(value)
        [ "#{field_accessor} < $#{param_num}", [ date_value ] ] if date_value
      when "is_after"
        date_value = extract_date_value(value)
        [ "#{field_accessor} > $#{param_num}", [ date_value ] ] if date_value
      else
        # Default to equality
        [ "#{field_accessor} = $#{param_num}", [ value.to_s ] ]
      end
    end

    def extract_date_value(value)
      if value.is_a?(Hash)
        value["date_mode_value"] || value["date"]
      else
        value.to_s
      end
    end

    def get_cache_count_status(table_name, now)
      result = execute_sql(
        "SELECT COUNT(*) as count, MIN(expires_at) as min_expires FROM #{table_name} WHERE expires_at > $1",
        [ now ]
      ).first

      return nil if result["count"].to_i.zero?

      min_expires = result["min_expires"]
      {
        "count" => result["count"].to_i,
        "expires_at" => min_expires&.iso8601,
        "is_valid" => true
      }
    end

    def get_records_cache_status(now, table_id: nil)
      sql = 'SELECT table_id, COUNT(*) as count, MIN(expires_at) as min_expires
             FROM cache_records WHERE expires_at > $1'
      params = [ now ]

      if table_id
        sql += " AND table_id = $2"
        params << table_id
      end

      sql += " GROUP BY table_id"

      results = execute_sql(sql, params)

      results.map do |row|
        {
          "table_id" => row["table_id"],
          "record_count" => row["count"].to_i,
          "expires_at" => row["min_expires"]&.iso8601,
          "is_valid" => true
        }
      end
    end

    # Get table name and solution for logging purposes
    def get_table_info_for_logging(table_id)
      result = execute_sql(
        "SELECT data->>'name' as name, solution_id FROM cache_tables WHERE table_id = $1",
        [ table_id ]
      ).first

      return {} unless result

      info = {}
      info[:table] = result["name"] if result["name"]

      # Look up solution name if we have solution_id
      if result["solution_id"]
        solution = execute_sql(
          "SELECT data->>'name' as name FROM cache_solutions WHERE solution_id = $1",
          [ result["solution_id"] ]
        ).first
        info[:solution] = solution["name"] if solution && solution["name"]
      end

      info
    end
  end

  # Simple query builder for PostgreSQL cache
  class PostgresQuery
    def initialize(cache, table_id)
      @cache = cache
      @table_id = table_id
      @filter = nil
      @sort = []
      @limit_val = nil
      @offset_val = nil
    end

    def where(conditions)
      # Convert simple conditions to filter format
      @filter ||= { "operator" => "and", "fields" => [] }

      conditions.each do |field, value|
        if value.is_a?(Hash)
          # Complex condition like {gte: 100}
          value.each do |op, v|
            comparison = case op.to_sym
            when :eq then "is"
            when :ne then "is_not"
            when :gt then "is_greater_than"
            when :gte then "is_equal_or_greater_than"
            when :lt then "is_less_than"
            when :lte then "is_equal_or_less_than"
            when :contains then "contains"
            when :has_any_of then "has_any_of"
            else "is"
            end
            @filter["fields"] << { "field" => field.to_s, "comparison" => comparison, "value" => v }
          end
        else
          @filter["fields"] << { "field" => field.to_s, "comparison" => "is", "value" => value }
        end
      end

      self
    end

    def order(field, direction = "ASC")
      @sort << { "field" => field.to_s, "direction" => direction }
      self
    end

    def limit(n)
      @limit_val = n.to_i
      self
    end

    def offset(n)
      @offset_val = n.to_i
      self
    end

    def execute
      @cache.get_cached_records(
        @table_id,
        filter: @filter,
        sort: @sort.any? ? @sort : nil,
        limit: @limit_val,
        offset: @offset_val
      ) || []
    end

    def count
      @cache.get_cached_record_count(@table_id, filter: @filter)
    end
  end
end
