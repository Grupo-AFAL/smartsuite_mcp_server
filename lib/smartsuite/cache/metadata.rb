# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'time'

module SmartSuite
  module Cache
    # Metadata handles table registry, schema management, and TTL configuration.
    #
    # This module is responsible for:
    # - Creating and managing dynamic cache tables for SmartSuite tables
    # - Mapping SmartSuite field types to SQL column types
    # - Handling schema evolution (adding new fields to existing tables)
    # - Managing TTL configuration per table
    # - Creating indexes for commonly-filtered fields
    #
    # @note Table and column names are human-readable (v1.6+) using field labels
    module Metadata
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
        used_column_names = Set.new(['id']) # Track to avoid duplicates

        fields.each do |field|
          field_slug = field['slug']
          next if field_slug == 'id' # Skip ID, already defined

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
          [table_id, sql_table_name, table_name, structure.to_json, field_mapping.to_json, Time.now.utc.iso8601,
           Time.now.utc.iso8601]
        )

        record_stat('table_creation', 'create', sql_table_name, { table_id: table_id, field_count: fields.size })

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
          { col_name => map_field_type_to_sql(field_type) }
        end
      end

      # Map SmartSuite field type to SQLite type
      #
      # @param field_type [String] SmartSuite field type
      # @return [String] SQLite column type
      def map_field_type_to_sql(field_type)
        return 'TEXT' if field_type.nil? || field_type.empty?

        case field_type.downcase
        # System fields
        when 'autonumber', 'comments_count'
          'INTEGER'
        when 'record_id', 'application_slug', 'application_id'
          'TEXT'
        when 'followed_by'
          'TEXT' # JSON array

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
          'INTEGER' # 0 or 1

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
          'SELECT * FROM cache_table_registry WHERE table_id = ?',
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
        old_fields = old_schema['structure']['structure'].to_set { |f| f['slug'] }
        new_fields_list = new_structure['structure'] || []
        new_fields = new_fields_list.to_set { |f| f['slug'] }

        added_fields = new_fields - old_fields
        return if added_fields.empty? # No new fields

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
          next unless should_index_field?(field_info)

          col_name = sanitize_column_name(field_slug)
          @db.execute("CREATE INDEX IF NOT EXISTS idx_#{sql_table_name}_#{col_name}
                     ON #{sql_table_name}(#{col_name})")
        end

        # Update schema metadata
        @db.execute(
          "UPDATE cache_table_registry
         SET structure = ?, field_mapping = ?, updated_at = ?
         WHERE table_id = ?",
          [new_structure.to_json, field_mapping.to_json, Time.now.utc.iso8601, table_id]
        )

        record_stat('schema_evolution', 'add_fields', sql_table_name,
                    { table_id: table_id, added_fields: added_fields.to_a })
      end

      # Get TTL for a table
      #
      # @param table_id [String] SmartSuite table ID
      # @return [Integer] TTL in seconds
      def get_table_ttl(table_id)
        result = @db.execute(
          'SELECT ttl_seconds FROM cache_ttl_config WHERE table_id = ?',
          [table_id]
        ).first

        result ? result['ttl_seconds'] : Layer::DEFAULT_TTL
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
                    { ttl_seconds: ttl_seconds, mutation_level: mutation_level })
      end
    end
  end
end
