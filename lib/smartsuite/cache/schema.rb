# frozen_string_literal: true

module SmartSuite
  module Cache
    # Centralized schema definitions for all SQLite tables
    #
    # This module provides SQL CREATE TABLE statements used by both
    # Cache::Layer and ApiStatsTracker to ensure consistent schema
    # definitions across the codebase.
    module Schema
      # Default TTL for cache entries (4 hours)
      DEFAULT_TTL = 4 * 60 * 60

      class << self
        # SQL for API stats tables (used by both ApiStatsTracker and Cache::Layer)
        #
        # @return [String] SQL statements for api_call_log, api_stats_summary, and cache_performance
        def api_stats_tables_sql
          <<-SQL
            -- API call tracking
            CREATE TABLE IF NOT EXISTS api_call_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_hash TEXT NOT NULL,
              method TEXT NOT NULL,
              endpoint TEXT NOT NULL,
              solution_id TEXT,
              table_id TEXT,
              timestamp TEXT NOT NULL,
              session_id TEXT DEFAULT 'legacy'
            );

            -- API statistics summary
            CREATE TABLE IF NOT EXISTS api_stats_summary (
              user_hash TEXT PRIMARY KEY,
              total_calls INTEGER DEFAULT 0,
              first_call TEXT,
              last_call TEXT
            );

            -- Cache performance tracking
            CREATE TABLE IF NOT EXISTS cache_performance (
              table_id TEXT PRIMARY KEY,
              hit_count INTEGER DEFAULT 0,
              miss_count INTEGER DEFAULT 0,
              last_access_time TEXT,
              record_count INTEGER DEFAULT 0,
              cache_size_bytes INTEGER DEFAULT 0,
              updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_api_call_log_user ON api_call_log(user_hash);
            CREATE INDEX IF NOT EXISTS idx_api_call_log_session ON api_call_log(session_id);
            CREATE INDEX IF NOT EXISTS idx_api_call_log_timestamp ON api_call_log(timestamp);
          SQL
        end

        # SQL for cache registry and TTL configuration tables
        #
        # @param default_ttl [Integer] default TTL in seconds
        # @return [String] SQL statements for cache_table_registry and cache_ttl_config
        def cache_registry_tables_sql(default_ttl: DEFAULT_TTL)
          <<-SQL
            -- Internal registry for dynamically-created SQL cache tables
            CREATE TABLE IF NOT EXISTS cache_table_registry (
              table_id TEXT PRIMARY KEY,
              sql_table_name TEXT NOT NULL UNIQUE,
              table_name TEXT,
              structure TEXT NOT NULL,
              field_mapping TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            -- TTL configuration per table
            CREATE TABLE IF NOT EXISTS cache_ttl_config (
              table_id TEXT PRIMARY KEY,
              ttl_seconds INTEGER NOT NULL DEFAULT #{default_ttl},
              mutation_level TEXT,
              notes TEXT,
              updated_at TEXT NOT NULL
            );

            -- Cache statistics
            CREATE TABLE IF NOT EXISTS cache_stats (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              category TEXT NOT NULL,
              operation TEXT NOT NULL,
              key TEXT,
              timestamp TEXT NOT NULL,
              metadata TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_stats_timestamp ON cache_stats(timestamp);
            CREATE INDEX IF NOT EXISTS idx_stats_category ON cache_stats(category);
          SQL
        end

        # SQL for cached data tables (solutions, tables, members, teams)
        #
        # @return [String] SQL statements for cached_solutions, cached_tables, etc.
        def cached_data_tables_sql
          <<-SQL
            -- Cache for solutions list
            CREATE TABLE IF NOT EXISTS cached_solutions (
              id TEXT PRIMARY KEY,
              slug TEXT,
              name TEXT,
              logo_icon TEXT,
              logo_color TEXT,
              description TEXT,
              status TEXT,
              hidden INTEGER,
              last_access TEXT,
              updated TEXT,
              created TEXT,
              created_by TEXT,
              records_count INTEGER,
              members_count INTEGER,
              applications_count INTEGER,
              automation_count INTEGER,
              has_demo_data INTEGER,
              delete_date TEXT,
              deleted_by TEXT,
              updated_by TEXT,
              permissions TEXT,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            );

            -- Cache for tables list
            CREATE TABLE IF NOT EXISTS cached_tables (
              id TEXT PRIMARY KEY,
              slug TEXT,
              name TEXT,
              solution_id TEXT,
              structure TEXT,
              created TEXT,
              created_by TEXT,
              status TEXT,
              hidden INTEGER DEFAULT 0,
              icon TEXT,
              primary_field TEXT,
              table_order INTEGER,
              permissions TEXT,
              field_permissions TEXT,
              record_term TEXT,
              fields_count_total INTEGER,
              fields_count_linkedrecordfield INTEGER,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            );

            -- Cache for members list
            CREATE TABLE IF NOT EXISTS cached_members (
              id TEXT PRIMARY KEY,
              email TEXT,
              role TEXT,
              status TEXT,
              status_updated_on TEXT,
              deleted_date TEXT,
              first_name TEXT,
              last_name TEXT,
              full_name TEXT,
              job_title TEXT,
              department TEXT,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            );

            -- Cache for teams list
            CREATE TABLE IF NOT EXISTS cached_teams (
              id TEXT PRIMARY KEY,
              name TEXT,
              description TEXT,
              members TEXT,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_cached_tables_solution ON cached_tables(solution_id);
            CREATE INDEX IF NOT EXISTS idx_cached_tables_expires ON cached_tables(expires_at);
            CREATE INDEX IF NOT EXISTS idx_cached_solutions_expires ON cached_solutions(expires_at);
            CREATE INDEX IF NOT EXISTS idx_cached_members_expires ON cached_members(expires_at);
            CREATE INDEX IF NOT EXISTS idx_cached_teams_expires ON cached_teams(expires_at);
          SQL
        end

        # All metadata tables SQL combined (used by Cache::Layer)
        #
        # @param default_ttl [Integer] default TTL in seconds
        # @return [String] all SQL statements combined
        def all_metadata_tables_sql(default_ttl: DEFAULT_TTL)
          [
            cache_registry_tables_sql(default_ttl: default_ttl),
            api_stats_tables_sql,
            cached_data_tables_sql
          ].join("\n")
        end
      end
    end
  end
end
