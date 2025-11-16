require 'sqlite3'
require 'json'
require 'time'
require 'digest'
require 'set'
require_relative 'cache_query'
require_relative '../query_logger'

module SmartSuite
  # CacheLayer provides persistent SQLite-based caching for SmartSuite data.
  #
  # Key features:
  # - Dynamic table creation (one SQL table per SmartSuite table)
  # - Proper SQL types for all 45+ SmartSuite field types
  # - Table-based TTL (all records expire together)
  # - Aggressive fetch strategy (cache all records at once)
  # - Configurable TTL per table
  #
  # Usage:
  #   cache = SmartSuite::CacheLayer.new
  #   cache.cache_table_records('table_123', records, ttl: 4.hours)
  #   results = cache.query('table_123').where(status: 'Active').execute
  class CacheLayer
    attr_reader :db, :db_path

    # Default TTL values in seconds (updated in v1.6)
    DEFAULT_TTL = 12 * 3600  # 12 hours (for records)
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

      # Set file permissions (owner read/write only)
      File.chmod(0600, @db_path) if File.exist?(@db_path)

      # In-memory performance counters (v1.6+)
      @perf_counters = Hash.new { |h, k| h[k] = {hits: 0, misses: 0} }
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
          description TEXT,
          structure TEXT,
          created TEXT,
          updated TEXT,
          created_by TEXT,
          updated_by TEXT,
          deleted_date TEXT,
          deleted_by TEXT,
          record_count INTEGER,
          cached_at TEXT NOT NULL,
          expires_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_cached_tables_solution ON cached_tables(solution_id);
        CREATE INDEX IF NOT EXISTS idx_cached_tables_expires ON cached_tables(expires_at);
        CREATE INDEX IF NOT EXISTS idx_cached_solutions_expires ON cached_solutions(expires_at);
      SQL

      # Migrate INTEGER timestamps to TEXT (ISO 8601)
      migrate_integer_timestamps_to_text

      # Create indexes after ensuring schema is up to date
      @db.execute_batch <<-SQL
        CREATE INDEX IF NOT EXISTS idx_api_call_log_user ON api_call_log(user_hash);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_session ON api_call_log(session_id);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_timestamp ON api_call_log(timestamp);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_solution ON api_call_log(solution_id);
        CREATE INDEX IF NOT EXISTS idx_api_call_log_table ON api_call_log(table_id);
      SQL
    end

    # Migrate old table name cached_table_schemas to cache_table_registry
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
        @db.execute("ALTER TABLE cached_table_schemas RENAME TO cache_table_registry")
        log_metric("→ Migrated table: cached_table_schemas → cache_table_registry")
      elsif old_table_exists && new_table_exists
        # Both tables exist (shouldn't happen, but handle gracefully)
        # Drop the old table to clean up
        @db.execute("DROP TABLE cached_table_schemas")
        log_metric("→ Cleaned up duplicate table: cached_table_schemas (cache_table_registry already exists)")
      end
    end

    # Migrate INTEGER timestamp columns to TEXT (ISO 8601) across all metadata tables
    def migrate_integer_timestamps_to_text
      # Check if any metadata tables have INTEGER timestamps (old format)
      tables_to_migrate = []

      # Check cache_table_registry
      cols = @db.execute("PRAGMA table_info(cache_table_registry)")
      created_col = cols.find { |c| c['name'] == 'created_at' }
      tables_to_migrate << 'cache_table_registry' if created_col && created_col['type'] == 'INTEGER'

      # Check cache_ttl_config
      cols = @db.execute("PRAGMA table_info(cache_ttl_config)")
      updated_col = cols.find { |c| c['name'] == 'updated_at' }
      tables_to_migrate << 'cache_ttl_config' if updated_col && updated_col['type'] == 'INTEGER'

      # Check cache_stats
      cols = @db.execute("PRAGMA table_info(cache_stats)")
      ts_col = cols.find { |c| c['name'] == 'timestamp' }
      tables_to_migrate << 'cache_stats' if ts_col && ts_col['type'] == 'INTEGER'

      # Check api_call_log
      cols = @db.execute("PRAGMA table_info(api_call_log)")
      ts_col = cols.find { |c| c['name'] == 'timestamp' }
      tables_to_migrate << 'api_call_log' if ts_col && ts_col['type'] == 'INTEGER'

      # Check api_stats_summary
      cols = @db.execute("PRAGMA table_info(api_stats_summary)")
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

    def migrate_cache_ttl_config_timestamps
      @db.execute_batch <<-SQL
        CREATE TABLE cache_ttl_config_new (
          table_id TEXT PRIMARY KEY,
          ttl_seconds INTEGER NOT NULL DEFAULT #{DEFAULT_TTL},
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
      QueryLogger.log_error("DB Query", e)
      raise
    end

    # Get or create a cache table for a SmartSuite table
    #
    # @param table_id [String] SmartSuite table ID
    # @param structure [Hash] SmartSuite table structure (from get_table API call)
    # @return [String] SQL table name
    def get_or_create_cache_table(table_id, structure)
      # Check if cache table already exists
      schema = get_cached_table_schema(table_id)

      if schema
        # Check if structure has changed (new fields added)
        handle_schema_evolution(table_id, structure, schema)
        return schema['sql_table_name']
      end

      # Create new cache table
      create_cache_table(table_id, structure)
    end

    # Create a new cache table for a SmartSuite table
    #
    # @param table_id [String] SmartSuite table ID
    # @param structure [Hash] SmartSuite table structure
    # @return [String] SQL table name
    def create_cache_table(table_id, structure)
      table_name = structure['name']

      # Generate human-readable SQL table name: cache_records_{sanitized_name}_{table_id}
      # Example: cache_records_customers_tbl_abc123 (v1.6+)
      sanitized_name = sanitize_table_name(table_name || 'table')
      sanitized_id = sanitize_table_name(table_id)
      sql_table_name = "cache_records_#{sanitized_name}_#{sanitized_id}"

      fields = structure['structure'] || []

      # Build column definitions with label-based names (v1.6+)
      columns = ['id TEXT PRIMARY KEY']
      field_mapping = {}
      used_column_names = Set.new(['id'])  # Track to avoid duplicates

      fields.each do |field|
        field_slug = field['slug']
        next if field_slug == 'id'  # Skip ID, already defined

        field_columns = get_field_columns(field)
        field_columns.each do |col_name, col_type|
          # Handle duplicate column names by appending suffix
          unique_col_name = deduplicate_column_name(col_name, used_column_names)
          used_column_names.add(unique_col_name)

          columns << "#{unique_col_name} #{col_type}"
          field_mapping[field_slug] ||= {}
          field_mapping[field_slug][unique_col_name] = col_type
        end
      end

      # Add metadata columns
      columns << 'cached_at INTEGER NOT NULL'
      columns << 'expires_at INTEGER NOT NULL'

      # Create table
      @db.execute("CREATE TABLE IF NOT EXISTS #{sql_table_name} (#{columns.join(', ')})")

      # Create indexes
      create_indexes_for_table(sql_table_name, fields, field_mapping)

      # Store schema metadata
      @db.execute(
        "INSERT OR REPLACE INTO cache_table_registry
         (table_id, sql_table_name, table_name, structure, field_mapping, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        [table_id, sql_table_name, table_name, structure.to_json, field_mapping.to_json, Time.now.utc.iso8601, Time.now.utc.iso8601]
      )

      record_stat('table_creation', 'create', sql_table_name, {table_id: table_id, field_count: fields.size})

      sql_table_name
    end

    # Get column definitions for a field (handles multi-column fields)
    #
    # Uses field labels for column names (v1.6+) with slug as fallback
    #
    # @param field [Hash] SmartSuite field definition
    # @return [Hash] Column name => SQL type mapping
    def get_field_columns(field)
      field_slug = field['slug']
      field_label = field['label']
      field_type = field['field_type'].downcase

      # Use field label for column name, fallback to slug (v1.6+)
      # Example: "Status" → "status" instead of "s7e8c12e98"
      col_name = if field_label && !field_label.empty?
        sanitize_column_name(field_label)
      else
        sanitize_column_name(field_slug)
      end

      case field_type
      when 'firstcreated'
        {
          'created_on' => 'TEXT',
          'created_by' => 'TEXT'
        }
      when 'lastupdated'
        {
          'updated_on' => 'TEXT',
          'updated_by' => 'TEXT'
        }
      when 'deleted_date'
        {
          'deleted_on' => 'TEXT',
          'deleted_by' => 'TEXT'
        }
      when 'daterangefield'
        {
          "#{col_name}_from" => 'TEXT',
          "#{col_name}_to" => 'TEXT'
        }
      when 'duedatefield'
        {
          "#{col_name}_from" => 'TEXT',
          "#{col_name}_to" => 'TEXT',
          "#{col_name}_is_overdue" => 'INTEGER',
          "#{col_name}_is_completed" => 'INTEGER'
        }
      when 'statusfield'
        {
          col_name => 'TEXT',
          "#{col_name}_updated_on" => 'TEXT'
        }
      when 'addressfield'
        {
          "#{col_name}_text" => 'TEXT',  # Searchable concatenated address
          "#{col_name}_json" => 'TEXT'   # Full JSON object
        }
      when 'fullnamefield'
        {
          col_name => 'TEXT',              # Full name (sys_root)
          "#{col_name}_json" => 'TEXT'     # Components
        }
      when 'smartdocfield'
        {
          "#{col_name}_preview" => 'TEXT',  # Searchable text
          "#{col_name}_json" => 'TEXT'      # Full content
        }
      when 'checklistfield'
        {
          "#{col_name}_json" => 'TEXT',
          "#{col_name}_total" => 'INTEGER',
          "#{col_name}_completed" => 'INTEGER'
        }
      when 'votefield'
        {
          "#{col_name}_count" => 'INTEGER',
          "#{col_name}_json" => 'TEXT'
        }
      when 'timetrackingfield'
        {
          "#{col_name}_json" => 'TEXT',
          "#{col_name}_total" => 'REAL'
        }
      else
        # Single column for most field types
        {col_name => map_field_type_to_sql(field_type)}
      end
    end

    # Map SmartSuite field type to SQLite type
    #
    # @param field_type [String] SmartSuite field type
    # @return [String] SQLite column type
    def map_field_type_to_sql(field_type)
      case field_type.downcase
      # System fields
      when 'autonumber', 'comments_count'
        'INTEGER'
      when 'record_id', 'application_slug', 'application_id'
        'TEXT'
      when 'followed_by'
        'TEXT'  # JSON array

      # Text fields
      when 'textfield', 'textarea', 'title'
        'TEXT'
      when 'emailfield', 'phonefield', 'linkfield'
        'TEXT'  # JSON array or single value
      when 'ipaddressfield', 'colorpickerfield', 'socialnetworkfield'
        'TEXT'  # JSON

      # Date fields
      when 'datefield'
        'TEXT'  # ISO 8601 string
      when 'durationfield'
        'REAL'  # Seconds
      when 'timefield'
        'TEXT'  # HH:MM:SS format

      # Number fields
      when 'numberfield', 'currencyfield', 'percentfield',
           'ratingfield', 'numbersliderfield', 'percentcompletefield'
        'REAL'

      # List fields
      when 'singleselectfield'
        'TEXT'  # Choice ID
      when 'multipleselectfield', 'tagfield'
        'TEXT'  # JSON array of IDs
      when 'yesnofield'
        'INTEGER'  # 0 or 1

      # Reference fields
      when 'assignedtofield', 'linkedrecordfield'
        'TEXT'  # JSON array
      when 'buttonfield'
        'TEXT'  # URL or null

      # File fields
      when 'filesfield', 'imagesfield', 'signaturefield'
        'TEXT'  # JSON

      else
        'TEXT'  # Default for unknown types
      end
    end

    # Create indexes for commonly-filtered fields
    #
    # @param sql_table_name [String] SQL table name
    # @param fields [Array<Hash>] SmartSuite field definitions
    # @param field_mapping [Hash] Field slug => column mapping
    def create_indexes_for_table(sql_table_name, fields, field_mapping)
      # Always index expires_at for TTL checks
      @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_expires
                   ON #{sql_table_name}(expires_at)")

      fields.each do |field|
        next unless should_index_field?(field)

        field_slug = field['slug']
        field_type = field['field_type'].downcase

        # Get primary column name for this field
        columns = field_mapping[field_slug]
        next unless columns

        # For multi-column fields, index the main columns
        case field_type
        when 'statusfield'
          col_name = sanitize_column_name(field_slug)
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}
                       ON #{sql_table_name}(#{col_name})")
        when 'daterangefield', 'duedatefield'
          col_name = sanitize_column_name(field_slug)
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}_from
                       ON #{sql_table_name}(#{col_name}_from)")
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}_to
                       ON #{sql_table_name}(#{col_name}_to)")
        when 'lastupdated'
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_updated_on
                       ON #{sql_table_name}(updated_on)")
        else
          # Single column index
          col_name = columns.keys.first
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}
                       ON #{sql_table_name}(#{col_name})")
        end
      end
    end

    # Determine if a field should be indexed
    #
    # @param field [Hash] SmartSuite field definition
    # @return [Boolean]
    def should_index_field?(field)
      field_type = field['field_type'].downcase

      # Always index these types (commonly filtered)
      always_index = %w[
        statusfield
        singleselectfield
        datefield
        duedatefield
        daterangefield
        currencyfield
        lastupdated
        assignedtofield
        yesnofield
      ]

      return true if always_index.include?(field_type)

      # Index primary fields
      return true if field['params'] && field['params']['primary']

      # Index title field
      return true if field['slug'] == 'title'

      false
    end

    # Sanitize table name for SQL
    #
    # @param table_id [String] SmartSuite table ID
    # @return [String] SQL-safe table name
    def sanitize_table_name(table_id)
      table_id.gsub(/[^a-zA-Z0-9_]/, '_')
    end

    # Sanitize column name for SQL
    #
    # @param field_slug [String] SmartSuite field slug
    # @return [String] SQL-safe column name
    def sanitize_column_name(field_slug)
      sanitized = field_slug.gsub(/[^a-zA-Z0-9_]/, '_').downcase

      # Ensure doesn't start with digit
      sanitized = "f_#{sanitized}" if sanitized =~ /^[0-9]/

      # Avoid SQLite reserved words
      reserved = %w[table column index select insert update delete where from join
                    order group by having limit offset union all distinct]
      sanitized = "field_#{sanitized}" if reserved.include?(sanitized)

      sanitized
    end

    # Deduplicate column name by appending suffix if needed (v1.6+)
    #
    # @param col_name [String] Proposed column name
    # @param used_names [Set] Set of already-used column names
    # @return [String] Unique column name
    def deduplicate_column_name(col_name, used_names)
      return col_name unless used_names.include?(col_name)

      # Append incrementing suffix until unique
      counter = 2
      loop do
        candidate = "#{col_name}_#{counter}"
        return candidate unless used_names.include?(candidate)
        counter += 1
      end
    end

    # Get cached table schema
    #
    # @param table_id [String] SmartSuite table ID
    # @return [Hash, nil] Schema metadata or nil if not cached
    def get_cached_table_schema(table_id)
      result = @db.execute(
        "SELECT * FROM cache_table_registry WHERE table_id = ?",
        [table_id]
      ).first

      return nil unless result

      # Parse JSON fields
      result['structure'] = JSON.parse(result['structure'])
      result['field_mapping'] = JSON.parse(result['field_mapping'])
      result
    end

    # Handle schema evolution (new fields added to table)
    #
    # @param table_id [String] SmartSuite table ID
    # @param new_structure [Hash] Updated SmartSuite table structure
    # @param old_schema [Hash] Existing cached schema
    def handle_schema_evolution(table_id, new_structure, old_schema)
      old_fields = old_schema['structure']['structure'].map { |f| f['slug'] }.to_set
      new_fields_list = new_structure['structure'] || []
      new_fields = new_fields_list.map { |f| f['slug'] }.to_set

      added_fields = new_fields - old_fields
      return if added_fields.empty?  # No new fields

      sql_table_name = old_schema['sql_table_name']
      field_mapping = old_schema['field_mapping']

      # Add new columns
      added_fields.each do |field_slug|
        field_info = new_fields_list.find { |f| f['slug'] == field_slug }
        next unless field_info

        field_columns = get_field_columns(field_info)
        field_columns.each do |col_name, col_type|
          @db.execute("ALTER TABLE #{sql_table_name} ADD COLUMN #{col_name} #{col_type}")
          field_mapping[field_slug] ||= {}
          field_mapping[field_slug][col_name] = col_type
        end

        # Create index if needed
        if should_index_field?(field_info)
          col_name = sanitize_column_name(field_slug)
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}
                       ON #{sql_table_name}(#{col_name})")
        end
      end

      # Update schema metadata
      @db.execute(
        "UPDATE cache_table_registry
         SET structure = ?, field_mapping = ?, updated_at = ?
         WHERE table_id = ?",
        [new_structure.to_json, field_mapping.to_json, Time.now.utc.iso8601, table_id]
      )

      record_stat('schema_evolution', 'add_fields', sql_table_name,
                  {table_id: table_id, added_fields: added_fields.to_a})
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
      @db.execute("DELETE FROM #{sql_table_name}")

      # Insert all records with same expiration time
      records.each do |record|
        insert_record(sql_table_name, table_id, structure, record, expires_at)
      end

      record_stat('records_cached', 'bulk_insert', table_id,
                  {record_count: records.size, ttl: ttl_seconds})

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
      columns = ['id', 'cached_at', 'expires_at']
      values = [record['id'], Time.now.utc.iso8601, expires_at]
      placeholders = ['?', '?', '?']

      # Extract values for each field
      fields_info.each do |field_info|
        field_slug = field_info['slug']
        next if field_slug == 'id'  # Already added
        next unless field_mapping[field_slug]

        field_value = record[field_slug]
        extracted_values = extract_field_value(field_info, field_value)

        extracted_values.each do |col_name, val|
          columns << col_name
          values << val
          placeholders << '?'
        end
      end

      # Execute INSERT
      sql = "INSERT OR REPLACE INTO #{sql_table_name} (#{columns.join(', ')})
             VALUES (#{placeholders.join(', ')})"

      @db.execute(sql, values)
    end

    # Extract value(s) for a field (handles multi-column fields)
    #
    # @param field_info [Hash] Field definition
    # @param value [Object] Field value from record
    # @return [Hash] Column name => extracted value
    def extract_field_value(field_info, value)
      return {} if value.nil?

      field_slug = field_info['slug']
      field_type = field_info['field_type'].downcase
      col_name = sanitize_column_name(field_slug)

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
        {col_name => parse_timestamp(value['date'])}
      when 'daterangefield'
        {
          "#{col_name}_from" => value['from_date'] ? parse_timestamp(value['from_date']['date']) : nil,
          "#{col_name}_to" => value['to_date'] ? parse_timestamp(value['to_date']['date']) : nil
        }
      when 'duedatefield'
        {
          "#{col_name}_from" => value['from_date'] && value['from_date']['date'] ?
                                  parse_timestamp(value['from_date']['date']) : nil,
          "#{col_name}_to" => value['to_date'] && value['to_date']['date'] ?
                                parse_timestamp(value['to_date']['date']) : nil,
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
        {col_name => value.to_f}
      when 'durationfield'
        {col_name => value.to_f}
      when 'yesnofield'
        {col_name => value ? 1 : 0}
      when 'emailfield', 'phonefield', 'linkfield', 'multipleselectfield',
           'tagfield', 'assignedtofield', 'linkedrecordfield',
           'filesfield', 'imagesfield', 'colorpickerfield',
           'ipaddressfield', 'socialnetworkfield', 'signaturefield',
           'followed_by'
        # Arrays and complex objects stored as JSON
        {col_name => value.is_a?(Array) || value.is_a?(Hash) ? value.to_json : value}
      else
        # Default: direct value or JSON
        {col_name => value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value}
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

    # Get TTL for a table
    #
    # @param table_id [String] SmartSuite table ID
    # @return [Integer] TTL in seconds
    def get_table_ttl(table_id)
      result = @db.execute(
        "SELECT ttl_seconds FROM cache_ttl_config WHERE table_id = ?",
        [table_id]
      ).first

      result ? result['ttl_seconds'] : DEFAULT_TTL
    end

    # Set TTL for a table
    #
    # @param table_id [String] SmartSuite table ID
    # @param ttl_seconds [Integer] TTL in seconds
    # @param mutation_level [String, nil] Mutation level preset
    # @param notes [String, nil] Optional notes
    def set_table_ttl(table_id, ttl_seconds, mutation_level: nil, notes: nil)
      @db.execute(
        "INSERT OR REPLACE INTO cache_ttl_config
         (table_id, ttl_seconds, mutation_level, notes, updated_at)
         VALUES (?, ?, ?, ?, ?)",
        [table_id, ttl_seconds, mutation_level, notes, Time.now.utc.iso8601]
      )

      record_stat('ttl_config', 'set', table_id,
                  {ttl_seconds: ttl_seconds, mutation_level: mutation_level})
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
        @db.execute("UPDATE #{sql_table_name} SET expires_at = 0")
        record_stat('invalidation', 'table_records', table_id)
      end

      # Also invalidate table structure metadata if structure changed
      if structure_changed
        db_execute("UPDATE cached_tables SET expires_at = 0 WHERE id = ?", table_id)
        record_stat('invalidation', 'table_structure', table_id)
        QueryLogger.log_cache_operation('invalidate', "table_structure:#{table_id}")
      end
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
      result = @db.execute(
        "SELECT COUNT(*) as count FROM #{sql_table_name} WHERE expires_at > ?",
        [Time.now.utc.iso8601]
      ).first

      result && result['count'] > 0
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
    rescue => e
      # Silent failure - stats are nice-to-have
      warn "Cache stat recording failed: #{e.message}"
    end

    # Create a query builder for a table
    #
    # @param table_id [String] SmartSuite table ID
    # @return [CacheQuery] Query builder
    #
    # Example:
    #   cache.query('table_123')
    #     .where(status: 'Active', revenue: {gte: 50000})
    #     .order('due_date')
    #     .limit(10)
    #     .execute
    def query(table_id)
      CacheQuery.new(self, table_id)
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
      db_execute("DELETE FROM cached_solutions")

      # Insert all solutions with fixed columns
      solutions.each do |solution|
        # Extract HTML from description if it exists
        description_html = if solution['description'].is_a?(Hash)
          solution['description']['html']
        else
          solution['description']
        end

        # Convert permissions to JSON if it exists
        permissions_json = solution['permissions'] ? solution['permissions'].to_json : nil

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

      record_stat('solutions_cached', 'bulk_insert', 'solutions', {count: solutions.size, ttl: ttl})

      QueryLogger.log_cache_operation('insert', 'solutions', count: solutions.size, ttl: ttl)

      solutions.size
    end

    # Get cached solutions list
    #
    # @return [Array<Hash>, nil] Array of solutions or nil if cache invalid
    def get_cached_solutions
      # Check if cache is valid
      return nil unless solutions_cache_valid?

      # Fetch all solutions
      results = db_execute(
        "SELECT * FROM cached_solutions WHERE expires_at > ?",
        Time.now.utc.iso8601
      )

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
        "SELECT COUNT(*) as count FROM cached_solutions WHERE expires_at > ?",
        Time.now.utc.iso8601
      ).first

      valid = result && result['count'] > 0

      QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', 'solutions')

      valid
    end

    # Invalidate solutions cache
    def invalidate_solutions_cache
      db_execute("UPDATE cached_solutions SET expires_at = 0")
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
        db_execute("DELETE FROM cached_tables WHERE solution_id = ?", solution_id)
      else
        db_execute("DELETE FROM cached_tables")
      end

      # Insert all tables with fixed columns
      tables.each do |table|
        # Convert structure to JSON if it exists
        structure_json = table['structure'] ? table['structure'].to_json : nil

        db_execute(
          "INSERT INTO cached_tables (
            id, slug, name, solution_id, description, structure,
            created, updated, created_by, updated_by, deleted_date, deleted_by, record_count,
            cached_at, expires_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          table['id'],
          table['slug'],
          table['name'],
          table['solution_id'],
          table['description'],
          structure_json,
          table['created'] ? parse_timestamp(table['created']) : nil,
          table['updated'] ? parse_timestamp(table['updated']) : nil,
          table['created_by'],
          table['updated_by'],
          table['deleted_date'] ? parse_timestamp(table['deleted_date']) : nil,
          table['deleted_by'],
          table['record_count'],
          cached_at,
          expires_at
        )
      end

      cache_key = solution_id ? "solution:#{solution_id}" : "all_tables"
      record_stat('table_list_cached', 'insert', cache_key, {count: tables.size, ttl: ttl})
      QueryLogger.log_cache_operation('insert', "table_list:#{cache_key}", count: tables.size, ttl: ttl)

      tables.size
    end

    # Get cached table list for a solution
    #
    # @param solution_id [String, nil] Solution ID (nil for all tables)
    # @return [Array<Hash>, nil] Array of tables or nil if cache invalid
    def get_cached_table_list(solution_id)
      # Check if cache is valid
      return nil unless table_list_cache_valid?(solution_id)

      # Fetch tables from cache
      if solution_id
        results = db_execute(
          "SELECT * FROM cached_tables WHERE solution_id = ? AND expires_at > ?",
          solution_id, Time.now.utc.iso8601
        )
      else
        results = db_execute(
          "SELECT * FROM cached_tables WHERE expires_at > ?",
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
        table['created'] = Time.at(row['created']).utc.iso8601 if row['created']
        table['updated'] = Time.at(row['updated']).utc.iso8601 if row['updated']
        table['created_by'] = row['created_by'] if row['created_by']
        table['updated_by'] = row['updated_by'] if row['updated_by']
        table['deleted_date'] = Time.at(row['deleted_date']).utc.iso8601 if row['deleted_date']
        table['deleted_by'] = row['deleted_by'] if row['deleted_by']
        table['record_count'] = row['record_count'] if row['record_count']

        table
      end

      cache_key = solution_id ? "solution:#{solution_id}" : "all_tables"
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
          "SELECT COUNT(*) as count FROM cached_tables WHERE solution_id = ? AND expires_at > ?",
          solution_id, Time.now.utc.iso8601
        ).first

        valid = result && result['count'] > 0
        QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', "table_list:solution:#{solution_id}")
        valid
      else
        result = db_execute(
          "SELECT COUNT(*) as count FROM cached_tables WHERE expires_at > ?",
          Time.now.utc.iso8601
        ).first

        valid = result && result['count'] > 0
        QueryLogger.log_cache_operation(valid ? 'valid' : 'expired', 'table_list:all_tables')
        valid
      end
    end

    # Invalidate table list cache
    #
    # @param solution_id [String, nil] Solution ID (nil for all tables)
    def invalidate_table_list_cache(solution_id)
      if solution_id
        db_execute("UPDATE cached_tables SET expires_at = 0 WHERE solution_id = ?", solution_id)
        record_stat('invalidation', 'table_list', solution_id)
        QueryLogger.log_cache_operation('invalidate', "table_list:solution:#{solution_id}")
      else
        db_execute("UPDATE cached_tables SET expires_at = 0")
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
        {
          'refreshed' => 'solutions',
          'message' => 'All solutions cache invalidated. Will refresh on next access.',
          'timestamp' => Time.now.utc.iso8601
        }
      when 'tables'
        invalidate_table_list_cache(solution_id)
        {
          'refreshed' => 'tables',
          'solution_id' => solution_id,
          'message' => solution_id ? "Table list for solution #{solution_id} invalidated." : "All tables cache invalidated.",
          'timestamp' => Time.now.utc.iso8601
        }
      when 'records'
        raise ArgumentError, "table_id is required for refreshing records cache" unless table_id
        invalidate_table_cache(table_id, structure_changed: false)
        {
          'refreshed' => 'records',
          'table_id' => table_id,
          'message' => "Records cache for table #{table_id} invalidated. Will refresh on next access.",
          'timestamp' => Time.now.utc.iso8601
        }
      else
        raise ArgumentError, "Unknown resource type: #{resource}. Use 'solutions', 'tables', or 'records'"
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
      status = {
        'timestamp' => now.iso8601,
        'solutions' => get_solutions_cache_status(now),
        'tables' => get_tables_cache_status(now),
        'records' => get_records_cache_status(now, table_id: table_id)
      }

      status
    end

    private

    # Get solutions cache status
    def get_solutions_cache_status(now)
      result = db_execute("SELECT COUNT(*) as count, MIN(expires_at) as first_expires FROM cached_solutions").first
      return nil if result['count'] == 0

      first_expires = Time.parse(result['first_expires'])
      {
        'count' => result['count'],
        'expires_at' => first_expires.iso8601,
        'time_remaining_seconds' => [(first_expires - now).to_i, 0].max,
        'is_valid' => first_expires > now
      }
    end

    # Get tables cache status
    def get_tables_cache_status(now)
      result = db_execute("SELECT COUNT(*) as count, MIN(expires_at) as first_expires FROM cached_tables").first
      return nil if result['count'] == 0

      first_expires = Time.parse(result['first_expires'])
      {
        'count' => result['count'],
        'expires_at' => first_expires.iso8601,
        'time_remaining_seconds' => [(first_expires - now).to_i, 0].max,
        'is_valid' => first_expires > now
      }
    end

    # Get records cache status (all tables or specific table)
    def get_records_cache_status(now, table_id: nil)
      # Get all cached table schemas
      schemas = db_execute("SELECT * FROM cache_table_registry")

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

        next nil if result['count'] == 0

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

    # Track cache hit for performance monitoring
    #
    # @param table_id [String] SmartSuite table ID
    def track_cache_hit(table_id)
      @perf_counters[table_id][:hits] += 1
      @perf_operations_since_flush += 1
      flush_performance_counters_if_needed
    end

    # Track cache miss for performance monitoring
    #
    # @param table_id [String] SmartSuite table ID
    def track_cache_miss(table_id)
      @perf_counters[table_id][:misses] += 1
      @perf_operations_since_flush += 1
      flush_performance_counters_if_needed
    end

    # Flush performance counters to database if threshold reached
    #
    # Flushes when either:
    # - 100 operations have occurred since last flush
    # - 5 minutes have passed since last flush
    def flush_performance_counters_if_needed
      should_flush = @perf_operations_since_flush >= 100 ||
                     (Time.now.utc - @perf_last_flush) >= 300 # 5 minutes

      flush_performance_counters if should_flush
    end

    # Flush all in-memory performance counters to database
    def flush_performance_counters
      return if @perf_counters.empty?

      now = Time.now.utc.iso8601

      @perf_counters.each do |table_id, counters|
        # Get current values from database
        current = db_execute(
          "SELECT hit_count, miss_count FROM cache_performance WHERE table_id = ?",
          table_id
        ).first

        if current
          # Update existing record
          new_hits = current['hit_count'] + counters[:hits]
          new_misses = current['miss_count'] + counters[:misses]

          db_execute(
            "UPDATE cache_performance
             SET hit_count = ?, miss_count = ?, last_access_time = ?, updated_at = ?
             WHERE table_id = ?",
            new_hits, new_misses, now, now, table_id
          )
        else
          # Insert new record
          db_execute(
            "INSERT INTO cache_performance
             (table_id, hit_count, miss_count, last_access_time, updated_at)
             VALUES (?, ?, ?, ?, ?)",
            table_id, counters[:hits], counters[:misses], now, now
          )
        end
      end

      # Reset counters
      @perf_counters.clear
      @perf_operations_since_flush = 0
      @perf_last_flush = Time.now.utc
    end

    # Get cache performance statistics
    #
    # @param table_id [String, nil] Optional table ID to filter by
    # @return [Array<Hash>] Performance statistics
    def get_cache_performance(table_id: nil)
      # Flush current counters first
      flush_performance_counters

      if table_id
        results = db_execute(
          "SELECT * FROM cache_performance WHERE table_id = ?",
          table_id
        )
      else
        results = db_execute("SELECT * FROM cache_performance ORDER BY last_access_time DESC")
      end

      results.map do |row|
        total = row['hit_count'] + row['miss_count']
        {
          'table_id' => row['table_id'],
          'hit_count' => row['hit_count'],
          'miss_count' => row['miss_count'],
          'total_operations' => total,
          'hit_rate' => total > 0 ? (row['hit_count'].to_f / total * 100).round(2) : 0.0,
          'last_access_time' => row['last_access_time'],
          'record_count' => row['record_count'],
          'cache_size_bytes' => row['cache_size_bytes']
        }
      end
    end

    # Close database connection
    def close
      # Flush any pending performance counters
      flush_performance_counters unless @perf_counters.empty?
      @db.close if @db
    end
  end
end
