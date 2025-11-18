# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'time'
require 'digest'
require_relative 'query'
require_relative 'migrations'
require_relative 'metadata'
require_relative 'performance'
require_relative '../response_formats'
require_relative '../fuzzy_matcher'
require_relative '../../query_logger'

module SmartSuite
  # Cache layer module
  #
  # Provides persistent SQLite-based caching for SmartSuite data.
  # Includes cache layer, query builder, migrations, metadata management, and performance tracking.
  module Cache
    # Layer provides persistent SQLite-based caching for SmartSuite data.
    #
    # Key features:
    # - Dynamic table creation (one SQL table per SmartSuite table)
    # - Proper SQL types for all 45+ SmartSuite field types
    # - Table-based TTL (all records expire together)
    # - Aggressive fetch strategy (cache all records at once)
    # - Configurable TTL per table
    #
    # Usage:
    #   cache = SmartSuite::Cache::Layer.new
    #   cache.cache_table_records('table_123', records, ttl: 4.hours)
    #   results = cache.query('table_123').where(status: 'Active').execute
    class Layer
      # Include modular functionality
      include Migrations
      include Metadata
      include Performance
      include ResponseFormats

      attr_reader :db, :db_path

      # Default TTL values in seconds (updated in v1.6)
      DEFAULT_TTL = 12 * 3600 # 12 hours (for records)
      TTL_PRESETS = {
        high_mutation: 1 * 3600,          # 1 hour (frequently changing data)
        medium_mutation: 12 * 3600,       # 12 hours (default for records)
        low_mutation: 7 * 24 * 3600,      # 7 days (solutions, tables, members)
        very_low_mutation: 30 * 24 * 3600 # 30 days (static reference data)
      }.freeze

      def initialize(db_path: nil)
        @db_path = db_path || File.expand_path('~/.smartsuite_mcp_cache.db')
        @db = SQLite3::Database.new(@db_path)
        @db.results_as_hash = true

        # Register custom SQLite functions
        register_custom_functions

        # Set file permissions (owner read/write only)
        File.chmod(0o600, @db_path) if File.exist?(@db_path)

        # In-memory performance counters (v1.6+)
        @perf_counters = Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } }
        @perf_operations_since_flush = 0
        @perf_last_flush = Time.now.utc

        setup_metadata_tables
      end

      # Set up metadata tables for cache management and API stats tracking
      def setup_metadata_tables
        # Migrate old table name first if it exists
        migrate_table_rename_if_needed

        @db.execute_batch <<-SQL
        -- Internal registry for dynamically-created SQL cache tables
        -- (not to be confused with SmartSuite table schema caching)
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
          ttl_seconds INTEGER NOT NULL DEFAULT #{DEFAULT_TTL},
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

        -- Cache performance tracking (v1.6+)
        CREATE TABLE IF NOT EXISTS cache_performance (
          table_id TEXT PRIMARY KEY,
          hit_count INTEGER DEFAULT 0,
          miss_count INTEGER DEFAULT 0,
          last_access_time TEXT,
          record_count INTEGER DEFAULT 0,
          cache_size_bytes INTEGER DEFAULT 0,
          updated_at TEXT NOT NULL
        );

        -- API call tracking (shared with ApiStatsTracker)
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

        -- API statistics summary (shared with ApiStatsTracker)
        CREATE TABLE IF NOT EXISTS api_stats_summary (
          user_hash TEXT PRIMARY KEY,
          total_calls INTEGER DEFAULT 0,
          first_call TEXT,
          last_call TEXT
        );

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

        CREATE INDEX IF NOT EXISTS idx_cached_tables_solution ON cached_tables(solution_id);
        CREATE INDEX IF NOT EXISTS idx_cached_tables_expires ON cached_tables(expires_at);
        CREATE INDEX IF NOT EXISTS idx_cached_solutions_expires ON cached_solutions(expires_at);
        SQL

        # Migrate INTEGER timestamps to TEXT (ISO 8601)
        migrate_integer_timestamps_to_text

        # Migrate cached_tables schema to match API response fields
        migrate_cached_tables_schema

        # Create indexes after ensuring schema is up to date
        @db.execute_batch <<-SQL
        CREATE INDEX IF NOT EXISTS idx_api_call_log_user ON api_call_log(user_hash);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_session ON api_call_log(session_id);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_timestamp ON api_call_log(timestamp);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_solution ON api_call_log(solution_id);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_table ON api_call_log(table_id);
        SQL
      end

      # Execute a SQL query with logging
      # @param sql [String] SQL query
      # @param params [Array] Query parameters (pass as individual args or as array)
      # @return [Array] Query results
      def db_execute(sql, *params)
        start_time = Time.now
        QueryLogger.log_db_query(sql, params)

        # SQLite3 gem expects params as array, not as splat args
        result = if params.empty?
                   @db.execute(sql)
                 else
                   @db.execute(sql, params)
                 end

        duration = Time.now - start_time
        QueryLogger.log_db_result(result.length, duration)

        result
      rescue StandardError => e
        QueryLogger.log_error('DB Query', e)
        raise
      end

      # Cache all records from a SmartSuite table
      #
      # @param table_id [String] SmartSuite table ID
      # @param structure [Hash] SmartSuite table structure
      # @param records [Array<Hash>] Array of record hashes
      # @param ttl [Integer] Time-to-live in seconds
      # @return [Integer] Number of records cached
      def cache_table_records(table_id, structure, records, ttl: nil)
        sql_table_name = get_or_create_cache_table(table_id, structure)
        ttl_seconds = ttl || get_table_ttl(table_id)
        expires_at = (Time.now + ttl_seconds).utc.iso8601

        # Clear existing records (re-fetch strategy)
        db_execute("DELETE FROM #{sql_table_name}")

        # Insert all records with same expiration time
        records.each do |record|
          insert_record(sql_table_name, table_id, structure, record, expires_at)
        end

        record_stat('records_cached', 'bulk_insert', table_id,
                    { record_count: records.size, ttl: ttl_seconds })

        records.size
      end

      # Insert a single record into cache table
      #
      # @param sql_table_name [String] SQL table name
      # @param table_id [String] SmartSuite table ID
      # @param structure [Hash] Table structure
      # @param record [Hash] Record data
      # @param expires_at [String] Expiration timestamp (ISO 8601)
      def insert_record(sql_table_name, table_id, structure, record, expires_at)
        schema = get_cached_table_schema(table_id)
        field_mapping = schema['field_mapping']
        fields_info = structure['structure'] || []

        # Build INSERT statement
        columns = %w[id cached_at expires_at]
        values = [record['id'], Time.now.utc.iso8601, expires_at]
        placeholders = ['?', '?', '?']

        # Extract values for each field
        fields_info.each do |field_info|
          field_slug = field_info['slug']
          next if field_slug == 'id' # Already added
          next unless field_mapping[field_slug]

          field_value = record[field_slug]

          # Use stored column names from field_mapping instead of regenerating
          stored_columns = field_mapping[field_slug]
          extracted_values = extract_field_value(field_info, field_value)

          # Map extracted values to stored column names
          stored_columns.each_key do |stored_col_name|
            # The extracted_values keys might differ from stored column names
            # Find the corresponding value by matching the column purpose
            val = find_matching_value(extracted_values, stored_col_name, field_info)

            columns << stored_col_name
            values << val
            placeholders << '?'
          end
        end

        # Execute INSERT
        sql = "INSERT OR REPLACE INTO #{sql_table_name} (#{columns.join(', ')})
             VALUES (#{placeholders.join(', ')})"

        db_execute(sql, values)
      end

      # Find matching value from extracted values for a stored column name
      #
      # @param extracted_values [Hash] Values extracted from field
      # @param stored_col_name [String] Stored column name in database
      # @param field_info [Hash] Field definition
      # @return [Object] Matched value or nil
      def find_matching_value(extracted_values, stored_col_name, field_info)
        # For simple fields with one column, just return the first value
        return extracted_values.values.first if extracted_values.size == 1

        # For multi-column fields, match by suffix pattern
        # e.g., stored "fecha_from" matches extracted "fecha_from"
        # or stored "t_tulo" matches extracted column with similar purpose
        field_type = field_info['field_type'].downcase
        field_slug = field_info['slug']

        # For special multi-column types, match by suffix
        case field_type
        when 'firstcreated'
          return extracted_values['created_on'] if stored_col_name == 'created_on'
          return extracted_values['created_by'] if stored_col_name == 'created_by'
        when 'lastupdated'
          return extracted_values['updated_on'] if stored_col_name == 'updated_on'
          return extracted_values['updated_by'] if stored_col_name == 'updated_by'
        when 'deleted_date'
          return extracted_values['deleted_on'] if stored_col_name == 'deleted_on'
          return extracted_values['deleted_by'] if stored_col_name == 'deleted_by'
        when 'statusfield'
          # Use label-based column name (same as get_field_columns)
          field_label = field_info['label']
          col_base = if field_label && !field_label.empty?
                       sanitize_column_name(field_label)
                     else
                       sanitize_column_name(field_slug)
                     end
          return extracted_values[col_base] if stored_col_name.end_with?(col_base) && !stored_col_name.include?('_updated_on')
          return extracted_values["#{col_base}_updated_on"] if stored_col_name.include?('_updated_on')
        when 'daterangefield', 'duedatefield'
          # Match by suffix pattern for daterange fields
          extracted_values.each do |extracted_col, val|
            # Match by suffix: "fecha_from" matches anything ending with "_from"
            if extracted_col.end_with?('_from') && stored_col_name.include?('_from')
              return val
            elsif extracted_col.end_with?('_to') && stored_col_name.include?('_to')
              return val
            elsif extracted_col.include?('_is_overdue') && stored_col_name.include?('_is_overdue')
              return val
            elsif extracted_col.include?('_is_completed') && stored_col_name.include?('_is_completed')
              return val
            end
          end
        end

        # For other complex types (address, fullname, smartdoc, etc.), match by suffix
        extracted_values.each do |extracted_col, val|
          # Try exact match first
          return val if extracted_col == stored_col_name

          # Try suffix match (e.g., "participantes_json" matches anything ending with "_json")
          if extracted_col.end_with?('_text') && stored_col_name.include?('_text')
            return val
          elsif extracted_col.end_with?('_json') && stored_col_name.include?('_json')
            return val
          elsif extracted_col.end_with?('_preview') && stored_col_name.include?('_preview')
            return val
          elsif extracted_col.end_with?('_total') && stored_col_name.include?('_total')
            return val
          elsif extracted_col.end_with?('_completed') && stored_col_name.include?('_completed')
            return val
          elsif extracted_col.end_with?('_count') && stored_col_name.include?('_count')
            return val
          end
        end

        # Default: return first value or nil
        extracted_values.values.first
      end

      # Extract value(s) for a field (handles multi-column fields)
      #
      # @param field_info [Hash] Field definition
      # @param value [Object] Field value from record
      # @return [Hash] Column name => extracted value
      def extract_field_value(field_info, value)
        return {} if value.nil?

        field_slug = field_info['slug']
        field_label = field_info['label']
        field_type = field_info['field_type'].downcase

        # Use field label for column name, fallback to slug (same as get_field_columns)
        col_name = if field_label && !field_label.empty?
                     sanitize_column_name(field_label)
                   else
                     sanitize_column_name(field_slug)
                   end

        case field_type
        when 'firstcreated'
          {
            'created_on' => parse_timestamp(value['on']),
            'created_by' => value['by']
          }
        when 'lastupdated'
          {
            'updated_on' => parse_timestamp(value['on']),
            'updated_by' => value['by']
          }
        when 'deleted_date'
          {
            'deleted_on' => value['date'] ? parse_timestamp(value['date']) : nil,
            'deleted_by' => value['deleted_by']
          }
        when 'datefield'
          { col_name => parse_timestamp(value['date']) }
        when 'daterangefield'
          {
            "#{col_name}_from" => value['from_date'] ? parse_timestamp(value['from_date']['date']) : nil,
            "#{col_name}_to" => value['to_date'] ? parse_timestamp(value['to_date']['date']) : nil
          }
        when 'duedatefield'
          {
            "#{col_name}_from" => (parse_timestamp(value['from_date']['date']) if value['from_date'] && value['from_date']['date']),
            "#{col_name}_to" => (parse_timestamp(value['to_date']['date']) if value['to_date'] && value['to_date']['date']),
            "#{col_name}_is_overdue" => value['is_overdue'] ? 1 : 0,
            "#{col_name}_is_completed" => value['status_is_completed'] ? 1 : 0
          }
        when 'statusfield'
          {
            col_name => value['value'],
            "#{col_name}_updated_on" => parse_timestamp(value['updated_on'])
          }
        when 'addressfield'
          {
            "#{col_name}_text" => value['sys_root'],
            "#{col_name}_json" => value.to_json
          }
        when 'fullnamefield'
          {
            col_name => value['sys_root'],
            "#{col_name}_json" => value.to_json
          }
        when 'smartdocfield'
          {
            "#{col_name}_preview" => value['preview'],
            "#{col_name}_json" => value.to_json
          }
        when 'checklistfield'
          {
            "#{col_name}_json" => value.to_json,
            "#{col_name}_total" => value['total_items'],
            "#{col_name}_completed" => value['completed_items']
          }
        when 'votefield'
          {
            "#{col_name}_count" => value['total_votes'],
            "#{col_name}_json" => value.to_json
          }
        when 'timetrackingfield'
          {
            "#{col_name}_json" => value.to_json,
            "#{col_name}_total" => value['total_duration']
          }
        when 'numberfield', 'currencyfield', 'percentfield'
          { col_name => value.to_f }
        when 'durationfield'
          { col_name => value.to_f }
        when 'yesnofield'
          { col_name => value ? 1 : 0 }
        when 'emailfield', 'phonefield', 'linkfield', 'multipleselectfield',
             'tagfield', 'assignedtofield', 'linkedrecordfield',
             'filesfield', 'imagesfield', 'colorpickerfield',
             'ipaddressfield', 'socialnetworkfield', 'signaturefield',
             'followed_by'
          # Arrays and complex objects stored as JSON
          { col_name => value.is_a?(Array) || value.is_a?(Hash) ? value.to_json : value }
        else
          # Default: direct value or JSON
          { col_name => value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value }
        end
      end

      # Parse and validate ISO 8601 timestamp
      #
      # @param timestamp_str [String] ISO 8601 timestamp
      # @return [String, nil] ISO 8601 timestamp or nil if invalid
      def parse_timestamp(timestamp_str)
        return nil if timestamp_str.nil?

        # Validate by parsing, then return original
        Time.parse(timestamp_str)
        timestamp_str
      rescue ArgumentError
        nil
      end

      # Invalidate cache for a table (force re-fetch on next query)
      #
      # Invalidates both the cached records AND the table structure metadata.
      # Use this when the table structure changes (fields added/updated/deleted).
      #
      # @param table_id [String] SmartSuite table ID
      # @param structure_changed [Boolean] Also invalidate table metadata (default: true)
      def invalidate_table_cache(table_id, structure_changed: true)
        schema = get_cached_table_schema(table_id)

        if schema
          sql_table_name = schema['sql_table_name']
          # Set expires_at to 0 to force re-fetch of cached records
          db_execute("UPDATE #{sql_table_name} SET expires_at = 0")
          record_stat('invalidation', 'table_records', table_id)
        end

        # Also invalidate table structure metadata if structure changed
        return unless structure_changed

        db_execute('UPDATE cached_tables SET expires_at = 0 WHERE id = ?', table_id)
        record_stat('invalidation', 'table_structure', table_id)
        QueryLogger.log_cache_operation('invalidate', "table_structure:#{table_id}")
      end

      # Check if cached records are valid (not expired)
      #
      # @param table_id [String] SmartSuite table ID
      # @return [Boolean] true if cache is valid
      def cache_valid?(table_id)
        schema = get_cached_table_schema(table_id)
        return false unless schema

        sql_table_name = schema['sql_table_name']

        # Check if any record exists and is not expired
        result = db_execute(
          "SELECT COUNT(*) as count FROM #{sql_table_name} WHERE expires_at > ?",
          [Time.now.utc.iso8601]
        ).first

        result && result['count'].to_i.positive?
      end

      # Record cache statistics
      #
      # @param category [String] Category of operation
      # @param operation [String] Type of operation
      # @param key [String] Key involved
      # @param metadata [Hash] Additional metadata
      def record_stat(category, operation, key, metadata = {})
        @db.execute(
          "INSERT INTO cache_stats (category, operation, key, timestamp, metadata)
         VALUES (?, ?, ?, ?, ?)",
          [category, operation, key, Time.now.utc.iso8601, metadata.to_json]
        )
      rescue StandardError => e
        # Silent failure - stats are nice-to-have
        warn "Cache stat recording failed: #{e.message}"
      end

      # Create a query builder for a table
      #
      # @param table_id [String] SmartSuite table ID
      # @return [Query] Query builder
      #
      # Example:
      #   cache.query('table_123')
      #     .where(status: 'Active', revenue: {gte: 50000})
      #     .order('due_date')
      #     .limit(10)
      #     .execute
      def query(table_id)
        Query.new(self, table_id)
      end

      # Get a single record from cache by record ID
      #
      # @param table_id [String] SmartSuite table ID
      # @param record_id [String] SmartSuite record ID
      # @return [Hash, nil] Record data or nil if not found/expired
      def get_cached_record(table_id, record_id)
        # Check if cache is valid first
        return nil unless cache_valid?(table_id)

        # Query for the specific record
        result = query(table_id).where(id: record_id).limit(1).execute.first

        if result
          QueryLogger.log_cache_operation('hit', "record:#{table_id}:#{record_id}")
          record_stat('record_cached', 'hit', table_id)
        end

        result
      rescue SQLite3::Exception => e
        warn "[Cache] Error reading cached record #{record_id}: #{e.message}"
        nil
      end

      # ========== Solution Caching ==========

      # Cache solutions list
      #
      # @param solutions [Array<Hash>] Array of solution hashes
      # @param ttl [Integer] Time-to-live in seconds (default: 7 days as of v1.6)
      # @return [Integer] Number of solutions cached
      def cache_solutions(solutions, ttl: 7 * 24 * 3600)
        expires_at = (Time.now + ttl).utc.iso8601
        cached_at = Time.now.utc.iso8601

        # Clear existing cached solutions
        db_execute('DELETE FROM cached_solutions')

        # Insert all solutions with fixed columns
        solutions.each do |solution|
          # Extract HTML from description if it exists
          description_html = if solution['description'].is_a?(Hash)
                               solution['description']['html']
                             else
                               solution['description']
                             end

          # Convert permissions to JSON if it exists
          permissions_json = solution['permissions']&.to_json

          db_execute(
            "INSERT INTO cached_solutions (
            id, slug, name, logo_icon, logo_color, description,
            status, hidden, last_access, updated, created, created_by,
            records_count, members_count, applications_count, automation_count,
            has_demo_data, delete_date, deleted_by, updated_by, permissions,
            cached_at, expires_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            solution['id'],
            solution['slug'],
            solution['name'],
            solution['logo_icon'],
            solution['logo_color'],
            description_html,
            solution['status'],
            solution['hidden'] ? 1 : 0,
            solution['last_access'] ? parse_timestamp(solution['last_access']) : nil,
            solution['updated'] ? parse_timestamp(solution['updated']) : nil,
            solution['created'] ? parse_timestamp(solution['created']) : nil,
            solution['created_by'],
            solution['records_count'],
            solution['members_count'],
            solution['applications_count'],
            solution['automation_count'],
            solution['has_demo_data'] ? 1 : 0,
            solution['delete_date'] ? parse_timestamp(solution['delete_date']) : nil,
            solution['deleted_by'],
            solution['updated_by'],
            permissions_json,
            cached_at,
            expires_at
          )
        end

        record_stat('solutions_cached', 'bulk_insert', 'solutions', { count: solutions.size, ttl: ttl })

        QueryLogger.log_cache_operation('insert', 'solutions', count: solutions.size, ttl: ttl)

        solutions.size
      end

      # Get cached solutions list
      #
      # @return [Array<Hash>, nil] Array of solutions or nil if cache invalid
      def get_cached_solutions(name: nil)
        # Check if cache is valid
        return nil unless solutions_cache_valid?

        # Build query with optional name filter using fuzzy matching
        results = if name
                    db_execute(
                      'SELECT * FROM cached_solutions WHERE expires_at > ? AND fuzzy_match(name, ?) = 1',
                      Time.now.utc.iso8601, name
                    )
                  else
                    db_execute(
                      'SELECT * FROM cached_solutions WHERE expires_at > ?',
                      Time.now.utc.iso8601
                    )
                  end

        return nil if results.empty?

        # Reconstruct solution hashes from fixed columns
        solutions = results.map do |row|
          solution = {
            'id' => row['id'],
            'name' => row['name'],
            'logo_icon' => row['logo_icon'],
            'logo_color' => row['logo_color']
          }

          # Add optional fields if present
          solution['slug'] = row['slug'] if row['slug']
          solution['description'] = row['description'] if row['description']
          solution['status'] = row['status'] if row['status']
          solution['hidden'] = row['hidden'] == 1 if row['hidden']
          solution['last_access'] = row['last_access'] if row['last_access']
          solution['updated'] = row['updated'] if row['updated']
          solution['created'] = row['created'] if row['created']
          solution['created_by'] = row['created_by'] if row['created_by']
          solution['records_count'] = row['records_count'] if row['records_count']
          solution['members_count'] = row['members_count'] if row['members_count']
          solution['applications_count'] = row['applications_count'] if row['applications_count']
          solution['automation_count'] = row['automation_count'] if row['automation_count']
          solution['has_demo_data'] = row['has_demo_data'] == 1 if row['has_demo_data']
          solution['delete_date'] = row['delete_date'] if row['delete_date']
          solution['deleted_by'] = row['deleted_by'] if row['deleted_by']
          solution['updated_by'] = row['updated_by'] if row['updated_by']
          solution['permissions'] = JSON.parse(row['permissions']) if row['permissions']

          solution
        end

        QueryLogger.log_cache_operation('hit', 'solutions', count: solutions.size)

        solutions
      end

      # Check if solutions cache is valid (not expired)
      #
      # @return [Boolean] true if cache is valid
      def solutions_cache_valid?
        result = db_execute(
          'SELECT COUNT(*) as count FROM cached_solutions WHERE expires_at > ?',
          Time.now.utc.iso8601
        ).first

        valid = result && result['count'].to_i.positive?

        QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', 'solutions')

        valid
      end

      # Invalidate solutions cache
      #
      # Cascades invalidation to all tables and their records
      def invalidate_solutions_cache
        # Invalidate table list (which cascades to records)
        invalidate_table_list_cache(nil)

        # Invalidate solutions
        db_execute('UPDATE cached_solutions SET expires_at = 0')
        record_stat('invalidation', 'solutions', 'solutions')
        QueryLogger.log_cache_operation('invalidate', 'solutions')
      end

      # ========== Table List Caching ==========

      # Cache table list for a solution
      #
      # @param solution_id [String, nil] Solution ID (nil for all tables)
      # @param tables [Array<Hash>] Array of table hashes
      # @param ttl [Integer] Time-to-live in seconds (default: 7 days as of v1.6)
      # @return [Integer] Number of tables cached
      def cache_table_list(solution_id, tables, ttl: 7 * 24 * 3600)
        expires_at = (Time.now + ttl).utc.iso8601
        cached_at = Time.now.utc.iso8601

        # Delete existing tables for this solution (or all if solution_id is nil)
        if solution_id
          db_execute('DELETE FROM cached_tables WHERE solution_id = ?', solution_id)
        else
          db_execute('DELETE FROM cached_tables')
        end

        # Insert all tables with fixed columns
        tables.each do |table|
          # Convert structure to JSON if it exists
          structure_json = table['structure']&.to_json

          # API returns 'solution' but we normalize to 'solution_id'
          solution_id_value = table['solution'] || table['solution_id']

          # API returns first_created as object with 'by' and 'on'
          created = table.dig('first_created', 'on')
          created_by = table.dig('first_created', 'by')

          # Convert permissions and field_permissions to JSON
          permissions_json = table['permissions']&.to_json
          field_permissions_json = table['field_permissions']&.to_json

          # Extract fields_count values
          fields_count_total = table.dig('fields_count', 'total')
          fields_count_linked = table.dig('fields_count', 'linkedrecordfield')

          # Convert hidden boolean to integer (0/1)
          hidden = table['hidden'] ? 1 : 0

          # Convert integer fields (default to nil if not present)
          table_order = table['order']&.to_i if table['order']
          fields_total = fields_count_total.to_i if fields_count_total
          fields_linked = fields_count_linked.to_i if fields_count_linked

          db_execute(
            "INSERT INTO cached_tables (
            id, slug, name, solution_id, structure,
            created, created_by,
            status, hidden, icon, primary_field, table_order,
            permissions, field_permissions, record_term,
            fields_count_total, fields_count_linkedrecordfield,
            cached_at, expires_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            table['id'],
            table['slug'],
            table['name'],
            solution_id_value,
            structure_json,
            created ? parse_timestamp(created) : nil,
            created_by,
            table['status'],
            hidden,
            table['icon'],
            table['primary_field'],
            table_order,
            permissions_json,
            field_permissions_json,
            table['record_term'],
            fields_total,
            fields_linked,
            cached_at,
            expires_at
          )
        end

        cache_key = solution_id ? "solution:#{solution_id}" : 'all_tables'
        record_stat('table_list_cached', 'insert', cache_key, { count: tables.size, ttl: ttl })
        QueryLogger.log_cache_operation('insert', "table_list:#{cache_key}", count: tables.size, ttl: ttl)

        tables.size
      end

      # Get cached table list for a solution
      #
      # @param solution_id [String, nil] Solution ID (nil for all tables)
      # @return [Array<Hash>, nil] Array of tables or nil if cache invalid
      # Get a single table from cache by table_id
      #
      # @param table_id [String] SmartSuite table ID
      # @return [Hash, nil] Table data with structure, or nil if not cached/expired
      def get_cached_table(table_id)
        result = db_execute(
          'SELECT id, name, solution_id, structure, slug, status, hidden, icon, primary_field,
                  expires_at
           FROM cached_tables
           WHERE id = ? AND expires_at > ?',
          table_id,
          Time.now.utc.iso8601
        ).first

        return nil unless result

        # Parse structure JSON back to array
        structure = result['structure'] ? JSON.parse(result['structure']) : []

        QueryLogger.log_cache_operation('hit', "table:#{table_id}")
        record_stat('table_cached', 'hit', table_id)

        {
          'id' => result['id'],
          'name' => result['name'],
          'solution_id' => result['solution_id'],
          'structure' => structure,
          'slug' => result['slug'],
          'status' => result['status'],
          'hidden' => result['hidden'],
          'icon' => result['icon'],
          'primary_field' => result['primary_field']
        }
      rescue SQLite3::Exception => e
        warn "[Cache] Error reading cached table #{table_id}: #{e.message}"
        nil
      end

      def get_cached_table_list(solution_id)
        # Check if cache is valid
        return nil unless table_list_cache_valid?(solution_id)

        # Fetch tables from cache
        results = if solution_id
                    db_execute(
                      'SELECT * FROM cached_tables WHERE solution_id = ? AND expires_at > ?',
                      solution_id, Time.now.utc.iso8601
                    )
                  else
                    db_execute(
                      'SELECT * FROM cached_tables WHERE expires_at > ?',
                      Time.now.utc.iso8601
                    )
                  end

        return nil if results.empty?

        # Reconstruct table hashes from fixed columns
        tables = results.map do |row|
          table = {
            'id' => row['id'],
            'name' => row['name'],
            'solution_id' => row['solution_id']
          }

          # Add optional fields if present
          table['slug'] = row['slug'] if row['slug']
          table['description'] = row['description'] if row['description']
          table['structure'] = JSON.parse(row['structure']) if row['structure']
          table['created'] = row['created'] if row['created']
          table['created_by'] = row['created_by'] if row['created_by']
          table['deleted_by'] = row['deleted_by'] if row['deleted_by']
          table['record_count'] = row['record_count'] if row['record_count']

          table
        end

        cache_key = solution_id ? "solution:#{solution_id}" : 'all_tables'
        QueryLogger.log_cache_operation('hit', "table_list:#{cache_key}", count: tables.size)

        tables
      end

      # Check if table list cache is valid (not expired)
      #
      # @param solution_id [String, nil] Solution ID (nil for all tables)
      # @return [Boolean] true if cache is valid
      def table_list_cache_valid?(solution_id)
        if solution_id
          result = db_execute(
            'SELECT COUNT(*) as count FROM cached_tables WHERE solution_id = ? AND expires_at > ?',
            solution_id, Time.now.utc.iso8601
          ).first

          valid = result && result['count'].to_i.positive?
          QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', "table_list:solution:#{solution_id}")
        else
          result = db_execute(
            'SELECT COUNT(*) as count FROM cached_tables WHERE expires_at > ?',
            Time.now.utc.iso8601
          ).first

          valid = result && result['count'].to_i.positive?
          QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', 'table_list:all_tables')
        end
        valid
      end

      # Invalidate table list cache
      #
      # Cascades invalidation to all records in the tables
      # @param solution_id [String, nil] Solution ID (nil for all tables)
      def invalidate_table_list_cache(solution_id)
        # Invalidate cached records first (cascade)
        invalidate_records_for_solution(solution_id)

        # Then invalidate table metadata
        if solution_id
          db_execute('UPDATE cached_tables SET expires_at = 0 WHERE solution_id = ?', solution_id)
          record_stat('invalidation', 'table_list', solution_id)
          QueryLogger.log_cache_operation('invalidate', "table_list:solution:#{solution_id}")
        else
          db_execute('UPDATE cached_tables SET expires_at = 0')
          record_stat('invalidation', 'table_list', 'all_tables')
          QueryLogger.log_cache_operation('invalidate', 'table_list:all_tables')
        end
      end

      # Refresh (invalidate) cache for specific resources
      #
      # Invalidates cache without refetching - data will be refreshed on next access.
      # Useful for forcing fresh data when you know it has changed.
      #
      # @param resource [String] Resource type: 'solutions', 'tables', or 'records'
      # @param table_id [String, nil] Table ID (required for 'records' resource)
      # @param solution_id [String, nil] Solution ID (optional for 'tables' resource)
      # @return [Hash] Refresh result with invalidated resource info
      def refresh_cache(resource, table_id: nil, solution_id: nil)
        case resource
        when 'solutions'
          invalidate_solutions_cache
          operation_response(
            'refresh',
            'All solutions cache invalidated. Will refresh on next access.',
            resource: 'solutions'
          )
        when 'tables'
          invalidate_table_list_cache(solution_id)
          message = solution_id ? "Table list for solution #{solution_id} invalidated." : 'All tables cache invalidated.'
          operation_response(
            'refresh',
            message,
            resource: 'tables',
            solution_id: solution_id
          )
        when 'records'
          raise ArgumentError, 'table_id is required for refreshing records cache' unless table_id

          invalidate_table_cache(table_id, structure_changed: false)
          operation_response(
            'refresh',
            "Records cache for table #{table_id} invalidated. Will refresh on next access.",
            resource: 'records',
            table_id: table_id
          )
        else
          raise ArgumentError, "Unknown resource type: #{resource}. Use 'solutions', 'tables', or 'records'"
        end
      end

      # Get list of table IDs for cache warming
      #
      # Returns either a user-specified list or automatically selects top N most accessed tables
      # based on cache performance metrics.
      #
      # @param tables [Array<String>, String, nil] Array of table IDs, 'auto', or nil for auto mode
      # @param count [Integer] Number of tables to return in auto mode (default: 5)
      # @return [Array<String>] List of table IDs to warm
      def get_tables_to_warm(tables: nil, count: 5)
        if tables.nil? || tables == 'auto'
          # Auto mode: get top N most accessed tables from cache_performance
          results = db_execute(
            "SELECT table_id FROM cache_performance
           ORDER BY (hit_count + miss_count) DESC
           LIMIT ?",
            count
          )
          results.map { |row| row['table_id'] }
        elsif tables.is_a?(Array)
          # Explicit list of table IDs
          tables
        elsif tables.is_a?(String)
          # Single table ID
          [tables]
        else
          []
        end
      end

      # Get cache status for solutions, tables, and records
      #
      # Shows cached_at, expires_at, time_remaining, record_count for each cached resource.
      # Helps users understand cache state and plan cache refreshes.
      #
      # @param table_id [String, nil] Optional table ID to show status for specific table
      # @return [Hash] Cache status information
      def get_cache_status(table_id: nil)
        now = Time.now.utc
        {
          'timestamp' => now.iso8601,
          'solutions' => get_solutions_cache_status(now),
          'tables' => get_tables_cache_status(now),
          'records' => get_records_cache_status(now, table_id: table_id)
        }
      end

      private

      # Register custom SQLite functions for advanced querying
      #
      # Registers:
      # - fuzzy_match(text, query): Fuzzy string matching with typo tolerance
      def register_custom_functions
        # Register fuzzy_match function
        # Returns 1 if text fuzzy matches query, 0 otherwise
        @db.create_function('fuzzy_match', 2) do |_func, text, query|
          # Handle NULL values
          next 0 if text.nil? || query.nil?

          # Use FuzzyMatcher module for matching logic
          SmartSuite::FuzzyMatcher.match?(text, query) ? 1 : 0
        end
      end

      # Get all table IDs for a solution from cached_tables
      #
      # @param solution_id [String] Solution ID
      # @return [Array<String>] Array of table IDs belonging to the solution
      def get_table_ids_for_solution(solution_id)
        results = db_execute(
          'SELECT id FROM cached_tables WHERE solution_id = ?',
          solution_id
        )
        results.map { |row| row['id'] }
      end

      # Invalidate all cached records for tables in a solution
      #
      # @param solution_id [String, nil] Solution ID (nil for all tables)
      def invalidate_records_for_solution(solution_id)
        table_ids = if solution_id
                      get_table_ids_for_solution(solution_id)
                    else
                      # Get all table IDs from cache_table_registry
                      schemas = db_execute('SELECT table_id FROM cache_table_registry')
                      schemas.map { |row| row['table_id'] }
                    end

        return if table_ids.empty?

        # Invalidate records for each table
        invalidated_count = 0
        table_ids.each do |table_id|
          schema = get_cached_table_schema(table_id)
          next unless schema

          sql_table_name = schema['sql_table_name']
          db_execute("UPDATE #{sql_table_name} SET expires_at = 0")
          record_stat('invalidation', 'table_records', table_id)
          invalidated_count += 1
        end

        QueryLogger.log_cache_operation(
          'invalidate',
          solution_id ? "records:solution:#{solution_id}" : 'records:all_tables',
          count: invalidated_count
        )
      end

      # Get solutions cache status
      def get_solutions_cache_status(now)
        result = db_execute('SELECT COUNT(*) as count, MIN(expires_at) as first_expires FROM cached_solutions').first
        return nil if result['count'].zero?

        # Handle invalid/missing timestamp gracefully
        return nil if result['first_expires'].nil? || result['first_expires'] == '0' || result['first_expires'].empty?

        first_expires = Time.parse(result['first_expires'])
        {
          'count' => result['count'],
          'expires_at' => first_expires.iso8601,
          'time_remaining_seconds' => [(first_expires - now).to_i, 0].max,
          'is_valid' => first_expires > now
        }
      rescue ArgumentError => e
        # If time parsing fails, return nil (invalid cache state)
        warn "Warning: Invalid timestamp in cached_solutions: #{result['first_expires']} - #{e.message}"
        nil
      end

      # Get tables cache status
      def get_tables_cache_status(now)
        result = db_execute('SELECT COUNT(*) as count, MIN(expires_at) as first_expires FROM cached_tables').first
        return nil if result['count'].zero?

        # Handle invalid/missing timestamp gracefully
        return nil if result['first_expires'].nil? || result['first_expires'] == '0' || result['first_expires'].empty?

        first_expires = Time.parse(result['first_expires'])
        {
          'count' => result['count'],
          'expires_at' => first_expires.iso8601,
          'time_remaining_seconds' => [(first_expires - now).to_i, 0].max,
          'is_valid' => first_expires > now
        }
      rescue ArgumentError => e
        # If time parsing fails, return nil (invalid cache state)
        warn "Warning: Invalid timestamp in cached_tables: #{result['first_expires']} - #{e.message}"
        nil
      end

      # Get records cache status (all tables or specific table)
      def get_records_cache_status(now, table_id: nil)
        # Get all cached table schemas
        schemas = db_execute('SELECT * FROM cache_table_registry')

        if table_id
          # Filter to specific table
          schemas = schemas.select { |s| s['table_id'] == table_id }
        end

        return [] if schemas.empty?

        schemas.map do |schema|
          sql_table_name = schema['sql_table_name']

          # Get record count and expiration
          result = db_execute(
            "SELECT COUNT(*) as count, MIN(expires_at) as first_expires FROM #{sql_table_name}"
          ).first

          next nil if result['count'].zero?

          first_expires = Time.parse(result['first_expires'])
          {
            'table_id' => schema['table_id'],
            'table_name' => schema['table_name'],
            'record_count' => result['count'],
            'cached_at' => Time.parse(schema['updated_at']).iso8601,
            'expires_at' => first_expires.iso8601,
            'time_remaining_seconds' => [(first_expires - now).to_i, 0].max,
            'is_valid' => first_expires > now
          }
        end.compact
      end

      public

      # Close database connection
      def close
        # Flush any pending performance counters
        flush_performance_counters unless @perf_counters.empty?
        @db&.close
      end
    end
  end
end
