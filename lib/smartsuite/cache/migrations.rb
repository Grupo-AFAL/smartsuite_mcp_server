# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'time'

module SmartSuite
  module Cache
    # Migrations handles database schema migrations for the cache layer.
    #
    # This module is responsible for:
    # - Migrating table names (e.g., cached_table_schemas → cache_table_registry)
    # - Converting INTEGER timestamps to TEXT (ISO 8601 format)
    # - Handling backward compatibility with older cache formats
    #
    # @note All migrations are idempotent and safe to run multiple times
    module Migrations
      # Migrate old table name cached_table_schemas to cache_table_registry
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_table_rename_if_needed
        # Check if old table name exists
        old_table_exists = @db.execute(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='cached_table_schemas'"
        ).first

        # Check if new table name already exists
        new_table_exists = @db.execute(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='cache_table_registry'"
        ).first

        # Only rename if old exists and new doesn't exist
        if old_table_exists && !new_table_exists
          # Rename table using ALTER TABLE (instant, no data copy)
          @db.execute('ALTER TABLE cached_table_schemas RENAME TO cache_table_registry')
          log_metric('→ Migrated table: cached_table_schemas → cache_table_registry')
        elsif old_table_exists && new_table_exists
          # Both tables exist (shouldn't happen, but handle gracefully)
          # Drop the old table to clean up
          @db.execute('DROP TABLE cached_table_schemas')
          log_metric('→ Cleaned up duplicate table: cached_table_schemas (cache_table_registry already exists)')
        end
      end

      # Migrate INTEGER timestamp columns to TEXT (ISO 8601) across all metadata tables
      #
      # Checks each metadata table for INTEGER timestamp columns and migrates them
      # to TEXT format using ISO 8601 timestamps.
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_integer_timestamps_to_text
        # Check if any metadata tables have INTEGER timestamps (old format)
        tables_to_migrate = []

        # Check cache_table_registry
        cols = @db.execute('PRAGMA table_info(cache_table_registry)')
        created_col = cols.find { |c| c['name'] == 'created_at' }
        tables_to_migrate << 'cache_table_registry' if created_col && created_col['type'] == 'INTEGER'

        # Check cache_ttl_config
        cols = @db.execute('PRAGMA table_info(cache_ttl_config)')
        updated_col = cols.find { |c| c['name'] == 'updated_at' }
        tables_to_migrate << 'cache_ttl_config' if updated_col && updated_col['type'] == 'INTEGER'

        # Check cache_stats
        cols = @db.execute('PRAGMA table_info(cache_stats)')
        ts_col = cols.find { |c| c['name'] == 'timestamp' }
        tables_to_migrate << 'cache_stats' if ts_col && ts_col['type'] == 'INTEGER'

        # Check api_call_log
        cols = @db.execute('PRAGMA table_info(api_call_log)')
        ts_col = cols.find { |c| c['name'] == 'timestamp' }
        tables_to_migrate << 'api_call_log' if ts_col && ts_col['type'] == 'INTEGER'

        # Check api_stats_summary
        cols = @db.execute('PRAGMA table_info(api_stats_summary)')
        first_col = cols.find { |c| c['name'] == 'first_call' }
        tables_to_migrate << 'api_stats_summary' if first_col && first_col['type'] == 'INTEGER'

        return if tables_to_migrate.empty?

        # Perform migration for each table
        tables_to_migrate.each do |table|
          case table
          when 'cache_table_registry'
            migrate_cache_table_registry_timestamps
          when 'cache_ttl_config'
            migrate_cache_ttl_config_timestamps
          when 'cache_stats'
            migrate_cache_stats_timestamps
          when 'api_call_log'
            migrate_api_call_log_timestamps
          when 'api_stats_summary'
            migrate_api_stats_summary_timestamps
          end
        end
      end

      # Migrate cache_table_registry timestamp columns from INTEGER to TEXT
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_cache_table_registry_timestamps
        # Create temp table with TEXT timestamps
        @db.execute_batch <<-SQL
        CREATE TABLE cache_table_registry_new (
          table_id TEXT PRIMARY KEY,
          sql_table_name TEXT NOT NULL UNIQUE,
          table_name TEXT,
          structure TEXT NOT NULL,
          field_mapping TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        INSERT INTO cache_table_registry_new
        SELECT table_id, sql_table_name, table_name, structure, field_mapping,
               datetime(created_at, 'unixepoch'),
               datetime(updated_at, 'unixepoch')
        FROM cache_table_registry;

        DROP TABLE cache_table_registry;
        ALTER TABLE cache_table_registry_new RENAME TO cache_table_registry;
        SQL
      end

      # Migrate cache_ttl_config timestamp columns from INTEGER to TEXT
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_cache_ttl_config_timestamps
        @db.execute_batch <<-SQL
        CREATE TABLE cache_ttl_config_new (
          table_id TEXT PRIMARY KEY,
          ttl_seconds INTEGER NOT NULL DEFAULT #{CacheLayer::DEFAULT_TTL},
          mutation_level TEXT,
          notes TEXT,
          updated_at TEXT NOT NULL
        );

        INSERT INTO cache_ttl_config_new
        SELECT table_id, ttl_seconds, mutation_level, notes,
               datetime(updated_at, 'unixepoch')
        FROM cache_ttl_config;

        DROP TABLE cache_ttl_config;
        ALTER TABLE cache_ttl_config_new RENAME TO cache_ttl_config;
        SQL
      end

      # Migrate cache_stats timestamp columns from INTEGER to TEXT
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_cache_stats_timestamps
        @db.execute_batch <<-SQL
        CREATE TABLE cache_stats_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          operation TEXT NOT NULL,
          key TEXT,
          timestamp TEXT NOT NULL,
          metadata TEXT
        );

        INSERT INTO cache_stats_new (id, category, operation, key, timestamp, metadata)
        SELECT id, category, operation, key,
               datetime(timestamp, 'unixepoch'),
               metadata
        FROM cache_stats;

        DROP TABLE cache_stats;
        ALTER TABLE cache_stats_new RENAME TO cache_stats;

        CREATE INDEX IF NOT EXISTS idx_stats_timestamp ON cache_stats(timestamp);
        CREATE INDEX IF NOT EXISTS idx_stats_category ON cache_stats(category);
        SQL
      end

      # Migrate api_call_log timestamp columns from INTEGER to TEXT
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_api_call_log_timestamps
        @db.execute_batch <<-SQL
        CREATE TABLE api_call_log_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_hash TEXT NOT NULL,
          method TEXT NOT NULL,
          endpoint TEXT NOT NULL,
          solution_id TEXT,
          table_id TEXT,
          timestamp TEXT NOT NULL,
          session_id TEXT DEFAULT 'legacy'
        );

        INSERT INTO api_call_log_new (id, user_hash, method, endpoint, solution_id, table_id, timestamp, session_id)
        SELECT id, user_hash, method, endpoint, solution_id, table_id,
               datetime(timestamp, 'unixepoch'),
               session_id
        FROM api_call_log;

        DROP TABLE api_call_log;
        ALTER TABLE api_call_log_new RENAME TO api_call_log;
        SQL
      end

      # Migrate api_stats_summary timestamp columns from INTEGER to TEXT
      #
      # @param db [SQLite3::Database] Database connection
      # @return [void]
      def migrate_api_stats_summary_timestamps
        @db.execute_batch <<-SQL
        CREATE TABLE api_stats_summary_new (
          user_hash TEXT PRIMARY KEY,
          total_calls INTEGER DEFAULT 0,
          first_call TEXT,
          last_call TEXT
        );

        INSERT INTO api_stats_summary_new
        SELECT user_hash, total_calls,
               datetime(first_call, 'unixepoch'),
               datetime(last_call, 'unixepoch')
        FROM api_stats_summary;

        DROP TABLE api_stats_summary;
        ALTER TABLE api_stats_summary_new RENAME TO api_stats_summary;
        SQL
      end

      private

      # Log migration metrics
      #
      # @param message [String] Log message
      # @return [void]
      def log_metric(message)
        warn "[Cache::Migrations] #{message}" if ENV['DEBUG']
      end
    end
  end
end
