require 'sqlite3'
require 'json'
require 'time'
require 'digest'
require_relative 'cache_query'

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

    # Default TTL values in seconds
    DEFAULT_TTL = 4 * 3600  # 4 hours
    TTL_PRESETS = {
      high_mutation: 1 * 3600,      # 1 hour
      medium_mutation: 4 * 3600,    # 4 hours (default)
      low_mutation: 12 * 3600,      # 12 hours
      very_low_mutation: 24 * 3600  # 24 hours
    }.freeze

    def initialize(db_path: nil)
      @db_path = db_path || File.expand_path('~/.smartsuite_mcp_cache.db')
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true

      # Set file permissions (owner read/write only)
      File.chmod(0600, @db_path) if File.exist?(@db_path)

      setup_metadata_tables
    end

    # Set up metadata tables for cache management
    def setup_metadata_tables
      @db.execute_batch <<-SQL
        -- Track dynamically-created cache tables
        CREATE TABLE IF NOT EXISTS cached_table_schemas (
          table_id TEXT PRIMARY KEY,
          sql_table_name TEXT NOT NULL UNIQUE,
          table_name TEXT,
          structure TEXT NOT NULL,
          field_mapping TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );

        -- TTL configuration per table
        CREATE TABLE IF NOT EXISTS cache_ttl_config (
          table_id TEXT PRIMARY KEY,
          ttl_seconds INTEGER NOT NULL DEFAULT #{DEFAULT_TTL},
          mutation_level TEXT,
          notes TEXT,
          updated_at INTEGER NOT NULL
        );

        -- Cache statistics
        CREATE TABLE IF NOT EXISTS cache_stats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          operation TEXT NOT NULL,
          key TEXT,
          timestamp INTEGER NOT NULL,
          metadata TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_stats_timestamp ON cache_stats(timestamp);
        CREATE INDEX IF NOT EXISTS idx_stats_category ON cache_stats(category);
      SQL
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
      sql_table_name = "cache_records_#{sanitize_table_name(table_id)}"
      table_name = structure['name']
      fields = structure['structure'] || []

      # Build column definitions
      columns = ['id TEXT PRIMARY KEY']
      field_mapping = {}

      fields.each do |field|
        field_slug = field['slug']
        next if field_slug == 'id'  # Skip ID, already defined

        field_columns = get_field_columns(field)
        field_columns.each do |col_name, col_type|
          columns << "#{col_name} #{col_type}"
          field_mapping[field_slug] ||= {}
          field_mapping[field_slug][col_name] = col_type
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
        "INSERT OR REPLACE INTO cached_table_schemas
         (table_id, sql_table_name, table_name, structure, field_mapping, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        [table_id, sql_table_name, table_name, structure.to_json, field_mapping.to_json, Time.now.to_i, Time.now.to_i]
      )

      record_stat('table_creation', 'create', sql_table_name, {table_id: table_id, field_count: fields.size})

      sql_table_name
    end

    # Get column definitions for a field (handles multi-column fields)
    #
    # @param field [Hash] SmartSuite field definition
    # @return [Hash] Column name => SQL type mapping
    def get_field_columns(field)
      field_slug = field['slug']
      field_type = field['field_type'].downcase
      col_name = sanitize_column_name(field_slug)

      case field_type
      when 'firstcreated'
        {
          'created_on' => 'INTEGER',
          'created_by' => 'TEXT'
        }
      when 'lastupdated'
        {
          'updated_on' => 'INTEGER',
          'updated_by' => 'TEXT'
        }
      when 'deleted_date'
        {
          'deleted_on' => 'INTEGER',
          'deleted_by' => 'TEXT'
        }
      when 'daterangefield'
        {
          "#{col_name}_from" => 'INTEGER',
          "#{col_name}_to" => 'INTEGER'
        }
      when 'duedatefield'
        {
          "#{col_name}_from" => 'INTEGER',
          "#{col_name}_to" => 'INTEGER',
          "#{col_name}_is_overdue" => 'INTEGER',
          "#{col_name}_is_completed" => 'INTEGER'
        }
      when 'statusfield'
        {
          col_name => 'TEXT',
          "#{col_name}_updated_on" => 'INTEGER'
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
        'INTEGER'  # Unix timestamp
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

    # Get cached table schema
    #
    # @param table_id [String] SmartSuite table ID
    # @return [Hash, nil] Schema metadata or nil if not cached
    def get_cached_table_schema(table_id)
      result = @db.execute(
        "SELECT * FROM cached_table_schemas WHERE table_id = ?",
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
        "UPDATE cached_table_schemas
         SET structure = ?, field_mapping = ?, updated_at = ?
         WHERE table_id = ?",
        [new_structure.to_json, field_mapping.to_json, Time.now.to_i, table_id]
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
      expires_at = Time.now.to_i + ttl_seconds

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
    # @param expires_at [Integer] Expiration timestamp
    def insert_record(sql_table_name, table_id, structure, record, expires_at)
      schema = get_cached_table_schema(table_id)
      field_mapping = schema['field_mapping']
      fields_info = structure['structure'] || []

      # Build INSERT statement
      columns = ['id', 'cached_at', 'expires_at']
      values = [record['id'], Time.now.to_i, expires_at]
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

    # Parse ISO timestamp to Unix timestamp
    #
    # @param timestamp_str [String] ISO 8601 timestamp
    # @return [Integer] Unix timestamp
    def parse_timestamp(timestamp_str)
      return nil if timestamp_str.nil?
      Time.parse(timestamp_str).to_i
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
        [table_id, ttl_seconds, mutation_level, notes, Time.now.to_i]
      )

      record_stat('ttl_config', 'set', table_id,
                  {ttl_seconds: ttl_seconds, mutation_level: mutation_level})
    end

    # Invalidate cache for a table (force re-fetch on next query)
    #
    # @param table_id [String] SmartSuite table ID
    def invalidate_table_cache(table_id)
      schema = get_cached_table_schema(table_id)
      return unless schema

      sql_table_name = schema['sql_table_name']

      # Set expires_at to 0 to force re-fetch
      @db.execute("UPDATE #{sql_table_name} SET expires_at = 0")

      record_stat('invalidation', 'table', table_id)
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
        [Time.now.to_i]
      ).first

      result && result['count'] > 0
    end

    # Get cache status for a table
    #
    # @param table_id [String] SmartSuite table ID
    # @return [Hash] Cache status information
    def get_cache_status(table_id)
      schema = get_cached_table_schema(table_id)
      return {status: 'not_cached', table_id: table_id} unless schema

      sql_table_name = schema['sql_table_name']

      # Get record count and expiration
      result = @db.execute(
        "SELECT COUNT(*) as count, MIN(cached_at) as cached_at, MIN(expires_at) as expires_at
         FROM #{sql_table_name}"
      ).first

      return {status: 'empty', table_id: table_id} unless result && result['count'] > 0

      now = Time.now.to_i
      expires_at = result['expires_at']
      time_remaining = expires_at - now

      {
        table_id: table_id,
        table_name: schema['table_name'],
        record_count: result['count'],
        cached_at: Time.at(result['cached_at']).utc.iso8601,
        expires_at: Time.at(expires_at).utc.iso8601,
        ttl_seconds: get_table_ttl(table_id),
        status: time_remaining > 0 ? 'valid' : 'expired',
        time_remaining_seconds: [time_remaining, 0].max
      }
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
        [category, operation, key, Time.now.to_i, metadata.to_json]
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

    # Close database connection
    def close
      @db.close if @db
    end
  end
end
