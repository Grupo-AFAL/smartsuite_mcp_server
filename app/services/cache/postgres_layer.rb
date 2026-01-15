# frozen_string_literal: true

require_relative "../../../lib/smart_suite/logger"
require_relative "../../../lib/smart_suite/date_mode_resolver"

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

      # Note: cache_single_table requires a table object (with id, solution_id, name)
      # which we don't have here. Table list caching is handled separately via
      # cache_table_list() when fetching tables from the API.

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
        # Use pg_trgm similarity for fuzzy search with typo tolerance
        # similarity() returns 0-1, we accept matches > 0.3 or ILIKE fallback
        sql += " AND (similarity(data->>'name', $2) > 0.3 OR data->>'name' ILIKE $3)"
        params << name
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
        # Use pg_trgm similarity for fuzzy search with typo tolerance
        # similarity() returns 0-1, we accept matches > 0.3 or ILIKE fallback
        param_idx = params.size + 1
        like_idx = params.size + 2
        sql += " AND (" \
               "similarity(data->>'full_name', $#{param_idx}) > 0.3 OR data->>'full_name' ILIKE $#{like_idx}" \
               " OR similarity(data->>'first_name', $#{param_idx}) > 0.3 OR data->>'first_name' ILIKE $#{like_idx}" \
               " OR similarity(data->>'last_name', $#{param_idx}) > 0.3 OR data->>'last_name' ILIKE $#{like_idx}" \
               " OR data->>'email' ILIKE $#{like_idx})"
        params << query
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

    # ========== Views (Reports) Caching ==========

    def cache_views(views, ttl: DEFAULT_TTL)
      now = Time.current
      expires_at = now + ttl

      # Create table if not exists
      execute_sql(<<~SQL)
        CREATE TABLE IF NOT EXISTS cache_views (
          id VARCHAR PRIMARY KEY,
          solution_id VARCHAR,
          application_id VARCHAR,
          data JSONB NOT NULL,
          cached_at TIMESTAMP NOT NULL,
          expires_at TIMESTAMP NOT NULL
        )
      SQL

      # Create indexes if they don't exist
      execute_sql("CREATE INDEX IF NOT EXISTS idx_cache_views_application ON cache_views(application_id)")
      execute_sql("CREATE INDEX IF NOT EXISTS idx_cache_views_solution ON cache_views(solution_id)")
      execute_sql("CREATE INDEX IF NOT EXISTS idx_cache_views_expires ON cache_views(expires_at)")

      # Clear existing cache
      execute_sql("DELETE FROM cache_views")

      # Insert all views
      views.each do |view|
        execute_sql(
          'INSERT INTO cache_views (id, solution_id, application_id, data, cached_at, expires_at)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (id) DO UPDATE SET solution_id = $2, application_id = $3, data = $4, cached_at = $5, expires_at = $6',
          [ view["id"], view["solution"], view["application"], view.to_json, now, expires_at ]
        )
      end

      SmartSuite::Logger.cache("CACHED", "views", count: views.size)
      views.size
    end

    def get_cached_views(table_id: nil, solution_id: nil)
      unless views_cache_valid?
        SmartSuite::Logger.cache("MISS", "views")
        self.class.record_miss!
        return nil
      end

      sql = "SELECT data FROM cache_views WHERE expires_at > $1"
      params = [ Time.current ]

      if table_id
        sql += " AND application_id = $2"
        params << table_id
      elsif solution_id
        sql += " AND solution_id = $2"
        params << solution_id
      end

      results = execute_sql(sql, params)
      if results.empty?
        SmartSuite::Logger.cache("MISS", "views", count: 0)
        self.class.record_miss!
        return nil
      end

      SmartSuite::Logger.cache("HIT", "views", count: results.size)
      self.class.record_hit!
      results.map { |row| JSON.parse(row["data"]) }
    end

    def views_cache_valid?
      # Check if table exists first
      table_exists = execute_sql(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'cache_views')"
      ).first&.fetch("exists", false)

      return false unless table_exists

      result = execute_sql(
        "SELECT COUNT(*) as count FROM cache_views WHERE expires_at > $1",
        [ Time.current ]
      ).first

      result && result["count"].to_i.positive?
    end

    def invalidate_views_cache
      execute_sql("DELETE FROM cache_views") if views_cache_valid?
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

    # ========== Metadata Storage ==========

    def metadata_get(key)
      # Create table if not exists
      ensure_metadata_table_exists

      result = execute_sql(
        "SELECT value FROM cache_metadata WHERE key = $1 AND (expires_at IS NULL OR expires_at > $2)",
        [ key, Time.current ]
      ).first

      return nil unless result

      result["value"]
    end

    def metadata_set(key, value, ttl: nil)
      ensure_metadata_table_exists

      now = Time.current
      expires_at = ttl ? now + ttl : nil

      execute_sql(
        'INSERT INTO cache_metadata (key, value, cached_at, expires_at) VALUES ($1, $2, $3, $4)
         ON CONFLICT (key) DO UPDATE SET value = $2, cached_at = $3, expires_at = $4',
        [ key, value.to_s, now, expires_at ]
      )
    end

    # ========== Overdue Flags Support ==========

    def update_overdue_flags(table_id, field_slug, overdue_ids)
      return 0 if overdue_ids.nil? || overdue_ids.empty?

      # Update the JSONB data to set is_overdue flag on records
      # This modifies the cached record data to include the overdue status
      updated_count = 0

      overdue_ids.each do |record_id|
        # Update the record's data to include is_overdue: true for the due date field
        result = execute_sql(
          "UPDATE cache_records SET data = jsonb_set(data, $1, 'true'::jsonb)
           WHERE table_id = $2 AND record_id = $3 AND expires_at > $4",
          [ "{#{field_slug},is_overdue}", table_id, record_id, Time.current ]
        )
        updated_count += 1 if result
      end

      updated_count
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
        "views" => get_cache_count_status("cache_views", now),
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
      when "views"
        invalidate_views_cache
        { success: true, message: "Views cache invalidated" }
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

    def ensure_metadata_table_exists
      execute_sql(<<~SQL)
        CREATE TABLE IF NOT EXISTS cache_metadata (
          key VARCHAR PRIMARY KEY,
          value TEXT,
          cached_at TIMESTAMP NOT NULL,
          expires_at TIMESTAMP
        )
      SQL
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
      # For status/single select fields that store value in nested object
      select_field_accessor = select_field_value_accessor(field)

      case comparison
      when "is"
        [ "#{select_field_accessor} = $#{param_num}", [ value.to_s ] ]
      when "is_not"
        [ "#{select_field_accessor} != $#{param_num}", [ value.to_s ] ]
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
        build_is_empty_condition(field, field_accessor)
      when "is_not_empty"
        build_is_not_empty_condition(field, field_accessor)
      when "has_any_of"
        if value.is_a?(Array) && value.any?
          # For JSON arrays, check if any value is present
          or_conditions = value.map.with_index do |v, i|
            "data->'#{sanitize_field_name(field)}' @> $#{param_num + i}::jsonb"
          end
          [ "(#{or_conditions.join(' OR ')})", value.map { |v| "[\"#{v}\"]" } ]
        else
          # Empty array means "has any of nothing" = always false = no matches
          [ "FALSE", [] ]
        end
      when "has_all_of"
        if value.is_a?(Array) && value.any?
          # For JSON arrays, check if ALL values are present
          and_conditions = value.map.with_index do |v, i|
            "data->'#{sanitize_field_name(field)}' @> $#{param_num + i}::jsonb"
          end
          [ "(#{and_conditions.join(' AND ')})", value.map { |v| "[\"#{v}\"]" } ]
        else
          [ "TRUE", [] ]
        end
      when "has_none_of"
        if value.is_a?(Array) && value.any?
          # For JSON arrays, check if NONE of the values are present
          and_conditions = value.map.with_index do |v, i|
            "NOT (data->'#{sanitize_field_name(field)}' @> $#{param_num + i}::jsonb)"
          end
          [ "(#{and_conditions.join(' AND ')})", value.map { |v| "[\"#{v}\"]" } ]
        else
          [ "TRUE", [] ]
        end
      when "is_any_of"
        # For single select fields, use IN()
        if value.is_a?(Array) && value.any?
          placeholders = value.map.with_index { |_, i| "$#{param_num + i}" }.join(", ")
          [ "#{select_field_accessor} IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "FALSE", [] ]
        end
      when "is_none_of"
        # For single select fields, use NOT IN()
        if value.is_a?(Array) && value.any?
          placeholders = value.map.with_index { |_, i| "$#{param_num + i}" }.join(", ")
          [ "#{select_field_accessor} NOT IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "TRUE", [] ]
        end
      when "file_name_contains"
        # For file fields (JSONB array), search filename
        sanitized = sanitize_field_name(field)
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'name' ILIKE $#{param_num})", [ "%#{value}%" ] ]
      when "file_type_is"
        # For file fields (JSONB array), match type
        sanitized = sanitize_field_name(field)
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'type' = $#{param_num})", [ value.to_s ] ]
      when "is_before"
        date_value = extract_date_value(value)
        date_accessor = date_field_accessor(field)
        [ "#{date_accessor} < $#{param_num}", [ date_value ] ] if date_value
      when "is_after"
        date_value = extract_date_value(value)
        date_accessor = date_field_accessor(field)
        [ "#{date_accessor} > $#{param_num}", [ date_value ] ] if date_value
      when "is_on_or_before"
        date_value = extract_date_value(value)
        date_accessor = date_field_accessor(field)
        [ "#{date_accessor} <= $#{param_num}", [ date_value ] ] if date_value
      when "is_on_or_after"
        date_value = extract_date_value(value)
        date_accessor = date_field_accessor(field)
        [ "#{date_accessor} >= $#{param_num}", [ date_value ] ] if date_value
      else
        # Default to equality
        [ "#{field_accessor} = $#{param_num}", [ value.to_s ] ]
      end
    end

    def extract_date_value(value)
      SmartSuite::DateModeResolver.extract_date_value(value)
    end

    # Creates a PostgreSQL accessor for status/single select fields that handles both:
    # - Simple values: "in_progress" (stored as string)
    # - Object values: {"value": "in_progress", "updated_on": "..."} (statusfield format)
    #
    # Uses COALESCE to try the nested object format first, then falls back to simple string.
    def select_field_value_accessor(field)
      sanitized = sanitize_field_name(field)
      <<~SQL.squish
        COALESCE(
          data->'#{sanitized}'->>'value',
          data->>'#{sanitized}'
        )
      SQL
    end

    # Creates a PostgreSQL accessor for date fields that handles both:
    # - Simple date fields: "2024-06-24" (stored as string)
    # - Date Range fields: {"to_date": {"date": "2024-06-24T00:00:00Z", ...}, ...}
    # - Due Date fields: {"to_date": "2024-06-24", ...} (date as string, not nested object)
    #
    # For Date Range/Due Date fields, we extract the date from to_date and normalize
    # it to YYYY-MM-DD format for comparison.
    # Returns NULL when no valid date is present to avoid incorrect string comparisons.
    def date_field_accessor(field)
      sanitized = sanitize_field_name(field)
      # COALESCE tries multiple formats:
      # 1. Date Range format: to_date.date (nested object with date key)
      # 2. Due Date format: to_date (string date directly)
      # 3. Simple date format: field value is a date string
      # Only returns value if it matches YYYY-MM-DD pattern to avoid JSON string comparison bugs
      <<~SQL.squish
        COALESCE(
          SUBSTRING(data->'#{sanitized}'->'to_date'->>'date' FROM 1 FOR 10),
          CASE
            WHEN data->'#{sanitized}'->>'to_date' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->'#{sanitized}'->>'to_date' FROM 1 FOR 10)
            ELSE NULL
          END,
          CASE
            WHEN data->>'#{sanitized}' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->>'#{sanitized}' FROM 1 FOR 10)
            ELSE NULL
          END
        )
      SQL
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

    # Build is_empty condition that handles all SmartSuite field types:
    # - NULL/empty/null JSON for simple fields
    # - Date Range fields: {"from_date": null, "to_date": null} should be empty
    # - Status fields: {"value": null} should be empty
    # - Arrays and objects
    def build_is_empty_condition(field, field_accessor)
      sanitized = sanitize_field_name(field)
      date_accessor = date_field_accessor(field)

      # A field is empty if:
      # 1. Basic empty checks: NULL, '', [], {}, JSON null
      # 2. Date Range format with null to_date: {"from_date": ..., "to_date": null}
      # 3. Date Range format with to_date object that has null date: {"to_date": {"date": null}}
      # 4. Status/select format with null value: {"value": null}
      [
        "(#{field_accessor} IS NULL OR #{field_accessor} = '' OR " \
        "data->'#{sanitized}' = '[]'::jsonb OR data->'#{sanitized}' = '{}'::jsonb OR " \
        "data->'#{sanitized}' = 'null'::jsonb OR " \
        "(jsonb_typeof(data->'#{sanitized}') = 'array' AND jsonb_array_length(data->'#{sanitized}') = 0) OR " \
        "(jsonb_typeof(data->'#{sanitized}') = 'object' AND #{date_accessor} IS NULL AND data->'#{sanitized}'->'value' IS NULL))",
        []
      ]
    end

    # Build is_not_empty condition - inverse of is_empty
    def build_is_not_empty_condition(field, field_accessor)
      sanitized = sanitize_field_name(field)
      date_accessor = date_field_accessor(field)

      # A field is NOT empty if it has actual usable content:
      # - Not NULL/empty string
      # - Not empty array/object
      # - For Date Range: has a valid to_date with actual date value
      # - For Status: has a valid value
      [
        "(#{field_accessor} IS NOT NULL AND #{field_accessor} != '' AND " \
        "data->'#{sanitized}' != '[]'::jsonb AND data->'#{sanitized}' != '{}'::jsonb AND " \
        "data->'#{sanitized}' != 'null'::jsonb AND " \
        "NOT (jsonb_typeof(data->'#{sanitized}') = 'array' AND jsonb_array_length(data->'#{sanitized}') = 0) AND " \
        "(jsonb_typeof(data->'#{sanitized}') != 'object' OR #{date_accessor} IS NOT NULL OR data->'#{sanitized}'->'value' IS NOT NULL))",
        []
      ]
    end
  end

  # Simple query builder for PostgreSQL cache
  #
  # Provides a chainable interface compatible with SmartSuite::Cache::Query.
  # Supports both simple AND filters via where() and complex OR filters via
  # build_condition_sql() and where_raw().
  class PostgresQuery
    def initialize(cache, table_id)
      @cache = cache
      @table_id = table_id
      @filter = nil
      @sort = []
      @limit_val = nil
      @offset_val = nil
      @raw_where_clauses = []
      @raw_where_params = []
    end

    # Build SQL clause for a single condition (for FilterBuilder compatibility)
    #
    # Returns SQL with ? placeholders (converted to $N during execution)
    # to allow multiple conditions to be combined without param numbering conflicts.
    #
    # @param field_slug [Symbol, String] Field name
    # @param condition [Object] Value or {operator => value} hash
    # @return [Array<String, Array>] [sql_clause, params]
    def build_condition_sql(field_slug, condition)
      field = field_slug.to_s

      if condition.is_a?(Hash)
        operator, value = condition.first
        comparison = operator_to_comparison(operator)
      else
        comparison = "is"
        value = condition
      end

      build_pg_condition(field, comparison, value)
    end

    # Add a raw SQL WHERE clause (for FilterBuilder compatibility)
    #
    # @param clause [String] SQL clause with ? placeholders
    # @param params [Array] Parameters to bind
    # @return [PostgresQuery] self for chaining
    def where_raw(clause, params = [])
      return self unless clause && !clause.empty?

      @raw_where_clauses << clause
      @raw_where_params.concat(params)
      self
    end

    # Get field type from cached schema (for FilterBuilder validation)
    #
    # @param field_slug [String, Symbol] Field slug
    # @return [String, nil] Field type or nil if not found
    def get_field_type(field_slug)
      schema = @cache.get_cached_table_schema(@table_id)
      return nil unless schema

      fields = schema["structure"] || []
      field_info = fields.find { |f| f["slug"] == field_slug.to_s }
      field_info&.dig("field_type")&.downcase
    end

    # Get field params from cached schema (for FilterBuilder date handling)
    #
    # @param field_slug [String, Symbol] Field slug
    # @return [Hash, nil] Field params or nil if not found
    def get_field_params(field_slug)
      schema = @cache.get_cached_table_schema(@table_id)
      return nil unless schema

      fields = schema["structure"] || []
      field_info = fields.find { |f| f["slug"] == field_slug.to_s }
      field_info&.dig("params")
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
            # Null check operators
            when :is_empty then "is_empty"
            when :is_not_empty then "is_not_empty"
            # Date operators - preserve for date_field_accessor handling
            when :is_before then "is_before"
            when :is_after then "is_after"
            when :is_on_or_before then "is_on_or_before"
            when :is_on_or_after then "is_on_or_after"
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
      if @raw_where_clauses.any?
        execute_with_raw_sql
      else
        @cache.get_cached_records(
          @table_id,
          filter: @filter,
          sort: @sort.any? ? @sort : nil,
          limit: @limit_val,
          offset: @offset_val
        ) || []
      end
    end

    def count
      if @raw_where_clauses.any?
        count_with_raw_sql
      else
        @cache.get_cached_record_count(@table_id, filter: @filter)
      end
    end

    private

    # Convert FilterBuilder operator symbols to comparison strings
    def operator_to_comparison(operator)
      case operator.to_sym
      when :eq then "is"
      when :ne then "is_not"
      when :gt then "is_greater_than"
      when :gte then "is_equal_or_greater_than"
      when :lt then "is_less_than"
      when :lte then "is_equal_or_less_than"
      when :contains then "contains"
      when :not_contains then "not_contains"
      when :has_any_of then "has_any_of"
      when :has_all_of then "has_all_of"
      when :has_none_of then "has_none_of"
      when :is_exactly then "is_exactly"
      when :is_any_of then "is_any_of"
      when :is_none_of then "is_none_of"
      when :is_empty then "is_empty"
      when :is_not_empty then "is_not_empty"
      when :is_before then "is_before"
      when :is_after then "is_after"
      when :is_on_or_before then "is_on_or_before"
      when :is_on_or_after then "is_on_or_after"
      when :between then "between"
      when :not_between then "not_between"
      when :file_name_contains then "file_name_contains"
      when :file_type_is then "file_type_is"
      else "is"
      end
    end

    # Build PostgreSQL JSONB condition with ? placeholders
    #
    # @param field [String] Field name
    # @param comparison [String] Comparison operator
    # @param value [Object] Value to compare
    # @return [Array<String, Array>] [sql_clause, params]
    def build_pg_condition(field, comparison, value)
      sanitized = field.gsub(/[^a-zA-Z0-9_]/, "")
      field_accessor = "data->>'#{sanitized}'"
      select_accessor = "COALESCE(data->'#{sanitized}'->>'value', data->>'#{sanitized}')"

      case comparison
      when "is"
        [ "#{select_accessor} = ?", [ value.to_s ] ]
      when "is_not"
        [ "#{select_accessor} != ?", [ value.to_s ] ]
      when "contains"
        [ "#{field_accessor} ILIKE ?", [ "%#{value}%" ] ]
      when "not_contains"
        [ "#{field_accessor} NOT ILIKE ?", [ "%#{value}%" ] ]
      when "is_greater_than"
        [ "(#{field_accessor})::numeric > ?", [ value.to_f ] ]
      when "is_less_than"
        [ "(#{field_accessor})::numeric < ?", [ value.to_f ] ]
      when "is_equal_or_greater_than"
        [ "(#{field_accessor})::numeric >= ?", [ value.to_f ] ]
      when "is_equal_or_less_than"
        [ "(#{field_accessor})::numeric <= ?", [ value.to_f ] ]
      when "is_empty"
        [ "(#{field_accessor} IS NULL OR #{field_accessor} = '' OR " \
          "data->'#{sanitized}' = '[]'::jsonb OR data->'#{sanitized}' = 'null'::jsonb)", [] ]
      when "is_not_empty"
        [ "(#{field_accessor} IS NOT NULL AND #{field_accessor} != '' AND " \
          "data->'#{sanitized}' != '[]'::jsonb AND data->'#{sanitized}' != 'null'::jsonb)", [] ]
      when "has_any_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "data->'#{sanitized}' @> ?::jsonb" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' OR ')})", params ]
        else
          [ "FALSE", [] ]
        end
      when "has_all_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "data->'#{sanitized}' @> ?::jsonb" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' AND ')})", params ]
        else
          [ "TRUE", [] ]
        end
      when "has_none_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "NOT (data->'#{sanitized}' @> ?::jsonb)" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' AND ')})", params ]
        else
          [ "TRUE", [] ]
        end
      when "is_any_of"
        if value.is_a?(Array) && value.any?
          placeholders = value.map { "?" }.join(", ")
          [ "#{select_accessor} IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "FALSE", [] ]
        end
      when "is_none_of"
        if value.is_a?(Array) && value.any?
          placeholders = value.map { "?" }.join(", ")
          [ "#{select_accessor} NOT IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "TRUE", [] ]
        end
      when "is_before"
        [ "#{date_field_accessor(sanitized)} < ?", [ value.to_s ] ]
      when "is_after"
        [ "#{date_field_accessor(sanitized)} > ?", [ value.to_s ] ]
      when "is_on_or_before"
        [ "#{date_field_accessor(sanitized)} <= ?", [ value.to_s ] ]
      when "is_on_or_after"
        [ "#{date_field_accessor(sanitized)} >= ?", [ value.to_s ] ]
      when "between"
        [ "#{field_accessor} BETWEEN ? AND ?", [ value[:min], value[:max] ] ]
      when "not_between"
        [ "(#{field_accessor} < ? OR #{field_accessor} > ?)", [ value[:min], value[:max] ] ]
      # File field operators (filefield only)
      # Files are stored as JSONB array: [{"name": "file.pdf", "type": "pdf", ...}, ...]
      when "file_name_contains"
        # Search for filename in JSONB array using JSONB path query
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'name' ILIKE ?)", [ "%#{value}%" ] ]
      when "file_type_is"
        # Search for file type in JSONB array
        # Valid types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'type' = ?)", [ value.to_s ] ]
      else
        [ "#{field_accessor} = ?", [ value.to_s ] ]
      end
    end

    # PostgreSQL accessor for date fields (handles nested SmartSuite date formats)
    def date_field_accessor(field)
      <<~SQL.squish
        COALESCE(
          SUBSTRING(data->'#{field}'->'to_date'->>'date' FROM 1 FOR 10),
          CASE
            WHEN data->'#{field}'->>'to_date' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->'#{field}'->>'to_date' FROM 1 FOR 10)
            ELSE NULL
          END,
          CASE
            WHEN data->>'#{field}' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->>'#{field}' FROM 1 FOR 10)
            ELSE NULL
          END
        )
      SQL
    end

    # Execute query with raw WHERE clauses (used for OR filters)
    def execute_with_raw_sql
      sql = "SELECT data FROM cache_records WHERE table_id = ? AND expires_at > ?"
      params = [ @table_id, Time.current ]

      # Add raw WHERE clauses
      @raw_where_clauses.each do |clause|
        sql += " AND (#{clause})"
      end
      params.concat(@raw_where_params)

      # Add sorting
      if @sort.any?
        sort_clauses = @sort.map do |s|
          field = s["field"] || s[:field]
          direction = (s["direction"] || s[:direction] || "asc").upcase
          direction = "ASC" unless %w[ASC DESC].include?(direction)
          "data->>'#{field.to_s.gsub(/[^a-zA-Z0-9_]/, '')}' #{direction}"
        end
        sql += " ORDER BY #{sort_clauses.join(', ')}"
      end

      # Add limit and offset
      if @limit_val
        sql += " LIMIT ?"
        params << @limit_val
      end
      if @offset_val
        sql += " OFFSET ?"
        params << @offset_val
      end

      # Convert ? placeholders to $N
      param_counter = 0
      sql = sql.gsub("?") { param_counter += 1; "$#{param_counter}" }

      results = execute_sql(sql, params)
      results.map { |row| JSON.parse(row["data"]) }
    end

    # Count records with raw WHERE clauses
    def count_with_raw_sql
      sql = "SELECT COUNT(*) as count FROM cache_records WHERE table_id = ? AND expires_at > ?"
      params = [ @table_id, Time.current ]

      @raw_where_clauses.each do |clause|
        sql += " AND (#{clause})"
      end
      params.concat(@raw_where_params)

      # Convert ? placeholders to $N
      param_counter = 0
      sql = sql.gsub("?") { param_counter += 1; "$#{param_counter}" }

      result = execute_sql(sql, params).first
      result ? result["count"].to_i : 0
    end

    def execute_sql(sql, params = [])
      conn = ActiveRecord::Base.connection.raw_connection
      result = conn.exec_params(sql, params)
      result.to_a
    end
  end
end
