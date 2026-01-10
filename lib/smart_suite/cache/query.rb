# frozen_string_literal: true

require "set"
require_relative "../logger"

module SmartSuite
  module Cache
    # Query provides a chainable query builder for cached records.
    #
    # Supports multi-criteria filtering, ordering, and limiting.
    #
    # Usage:
    #   cache.query('table_123')
    #     .where(status: 'Active')
    #     .where(revenue: {gte: 50000})
    #     .order('due_date', 'ASC')
    #     .limit(10)
    #     .execute
    class Query
      attr_reader :cache, :table_id

      # Field type categorization for proper operator handling
      JSON_ARRAY_FIELD_TYPES = %w[
        userfield
        multipleselectfield
        linkedrecordfield
        filefield
        tagsfield
      ].freeze

      TEXT_FIELD_TYPES = %w[
        textfield
        textareafield
        richtextareafield
        emailfield
        phonefield
        linkfield
      ].freeze

      def initialize(cache, table_id)
        @cache = cache
        @table_id = table_id
        @where_clauses = []
        @params = []
        @order_clauses = []
        @limit_clause = nil
        @offset_clause = nil
      end

      # Check if field type is a JSON array field
      def json_array_field?(field_type)
        JSON_ARRAY_FIELD_TYPES.include?(field_type)
      end

      # Check if field type is a text field
      def text_field?(field_type)
        TEXT_FIELD_TYPES.include?(field_type)
      end

      # Add WHERE conditions
      #
      # @param conditions [Hash] Field => value or {operator => value} mappings
      # @return [CacheQuery] self for chaining
      #
      # Examples:
      #   .where(status: 'Active')
      #   .where(revenue: {gte: 50000})
      #   .where(project_name: {contains: 'Alpha'})
      #   .where(assigned_to: {has_any_of: ['user_123']})
      def where(conditions)
        schema = @cache.get_cached_table_schema(@table_id)
        raise "Table #{@table_id} not cached" unless schema

        field_mapping = schema["field_mapping"]
        structure = schema["structure"]
        fields_info = structure["structure"] || []

        conditions.each do |field_slug, condition|
          field_slug_str = field_slug.to_s

          # Special handling for built-in 'id' field
          if field_slug_str == "id"
            @where_clauses << "id = ?"
            @params << condition
            next
          end

          # For daterangefield and duedatefield sub-fields (e.g., "s31437fa81.to_date"),
          # extract the base field slug to find the field info
          base_field_slug = field_slug_str.sub(/\.(from_date|to_date)$/, "")

          # Find field info using base slug
          field_info = fields_info.find { |f| f["slug"] == base_field_slug }
          next unless field_info # Skip unknown fields

          # Get SQL column name(s) using base slug (field_mapping uses base slug)
          columns = field_mapping[base_field_slug]
          next unless columns

          # Build condition (pass full field_slug_str for .from_date/.to_date handling)
          clause, params = build_condition(field_info, columns, condition, field_slug_str)
          @where_clauses << clause
          @params.concat(params)
        end

        self
      end

      # Add a raw SQL WHERE clause
      #
      # This is useful for complex conditions like nested AND/OR groups
      # that can't be expressed through the standard `where` interface.
      #
      # @param clause [String] Raw SQL clause (e.g., "(status = ? OR priority = ?)")
      # @param params [Array] Parameters to bind to the clause
      # @return [CacheQuery] self for chaining
      #
      # @example
      #   .where_raw("(status = ? OR priority > ?)", ["Active", 5])
      def where_raw(clause, params = [])
        @where_clauses << clause
        @params.concat(params)
        self
      end

      # Build SQL clause for a single condition (without adding to query)
      #
      # This is useful for constructing complex nested filter groups.
      # Returns the SQL fragment and params that would be generated for a condition.
      #
      # @param field_slug [String, Symbol] Field to filter on
      # @param condition [Object] Condition value or operator hash
      # @return [Array<String, Array>] [sql_clause, params] or [nil, []] if field not found
      #
      # @example
      #   clause, params = query.build_condition_sql(:status, "Active")
      #   #=> ["status_col = ?", ["Active"]]
      #   clause, params = query.build_condition_sql(:priority, {gt: 5})
      #   #=> ["priority_col > ?", [5]]
      def build_condition_sql(field_slug, condition)
        schema = @cache.get_cached_table_schema(@table_id)
        return [ nil, [] ] unless schema

        field_mapping = schema["field_mapping"]
        structure = schema["structure"]
        fields_info = structure["structure"] || []
        field_slug_str = field_slug.to_s

        # Special handling for built-in 'id' field
        if field_slug_str == "id"
          return [ "id = ?", [ condition ] ]
        end

        # For daterangefield and duedatefield sub-fields
        base_field_slug = field_slug_str.sub(/\.(from_date|to_date)$/, "")

        # Find field info using base slug
        field_info = fields_info.find { |f| f["slug"] == base_field_slug }
        return [ nil, [] ] unless field_info

        # Get SQL column name(s)
        columns = field_mapping[base_field_slug]
        return [ nil, [] ] unless columns

        # Build and return the condition
        build_condition(field_info, columns, condition, field_slug_str)
      end

      # Get the field type for a given field slug.
      #
      # This is useful for filter validation to check operator compatibility.
      #
      # @param field_slug [String, Symbol] Field slug to look up
      # @return [String, nil] Field type (lowercase) or nil if not found
      #
      # @example
      #   query.get_field_type("status")  #=> "statusfield"
      #   query.get_field_type("amount")  #=> "numberfield"
      def get_field_type(field_slug)
        schema = @cache.get_cached_table_schema(@table_id)
        return nil unless schema

        structure = schema["structure"]
        fields_info = structure["structure"] || []
        field_slug_str = field_slug.to_s

        # Handle daterangefield sub-fields (e.g., "s31437fa81.to_date")
        base_field_slug = field_slug_str.sub(/\.(from_date|to_date)$/, "")

        field_info = fields_info.find { |f| f["slug"] == base_field_slug }
        return nil unless field_info

        field_info["field_type"]&.downcase
      end

      # Get the field params for a given field slug.
      #
      # This is useful for checking field-specific settings like include_time for date fields.
      #
      # @param field_slug [String, Symbol] Field slug to look up
      # @return [Hash, nil] Field params hash or nil if not found
      #
      # @example
      #   query.get_field_params("due_date")  #=> {"include_time" => true, ...}
      def get_field_params(field_slug)
        schema = @cache.get_cached_table_schema(@table_id)
        return nil unless schema

        structure = schema["structure"]
        fields_info = structure["structure"] || []
        field_slug_str = field_slug.to_s

        # Handle daterangefield sub-fields (e.g., "s31437fa81.to_date")
        base_field_slug = field_slug_str.sub(/\.(from_date|to_date)$/, "")

        field_info = fields_info.find { |f| f["slug"] == base_field_slug }
        return nil unless field_info

        field_info["params"]
      end

      # Add ORDER BY clause
      #
      # Can be called multiple times to add additional sort criteria.
      #
      # @param field_slug [String, Symbol] Field to order by
      # @param direction [String] 'ASC' or 'DESC'
      # @return [CacheQuery] self for chaining
      def order(field_slug, direction = "ASC")
        schema = @cache.get_cached_table_schema(@table_id)
        return self unless schema

        field_mapping = schema["field_mapping"]
        structure = schema["structure"]
        fields_info = structure["structure"] || []

        columns = field_mapping[field_slug.to_s]

        if columns
          # Find field info to check field type
          field_info = fields_info.find { |f| f["slug"] == field_slug.to_s }
          field_type = field_info ? field_info["field_type"].downcase : nil

          # Select appropriate column based on field type (same logic as build_condition)
          # For duedatefield and daterangefield, SmartSuite API uses to_date for sorting
          col_name = if %w[duedatefield daterangefield].include?(field_type)
                       # Check if sorting by sub-field (e.g., due_date.from_date)
                       if field_slug.to_s.end_with?(".from_date")
                         columns.keys.find { |k| k.end_with?("_from") } || columns.keys.first
                       elsif field_slug.to_s.end_with?(".to_date")
                         columns.keys.find { |k| k.end_with?("_to") } || columns.keys.first
                       else
                         # Default: use to_date column (matches SmartSuite API behavior)
                         columns.keys.find { |k| k.end_with?("_to") } || columns.keys.first
                       end
          else
                       # For other field types, use first column
                       columns.keys.first
          end

          @order_clauses << "#{col_name} #{direction.upcase}"
        end

        self
      end

      # Add LIMIT clause
      #
      # @param n [Integer] Maximum number of results
      # @return [CacheQuery] self for chaining
      def limit(n)
        @limit_clause = "LIMIT #{n.to_i}"
        self
      end

      # Add OFFSET clause
      #
      # @param n [Integer] Number of results to skip
      # @return [CacheQuery] self for chaining
      def offset(n)
        @offset_clause = "OFFSET #{n.to_i}"
        self
      end

      # Execute the query
      #
      # @return [Array<Hash>] Query results with original field slugs as keys
      def execute
        schema = @cache.get_cached_table_schema(@table_id)
        return [] unless schema

        sql_table_name = schema["sql_table_name"]

        # Build SQL query
        sql = "SELECT * FROM #{sql_table_name}"

        # Add WHERE clauses
        sql += " WHERE #{@where_clauses.join(' AND ')}" if @where_clauses.any?

        # Add ORDER BY (support multiple sort criteria)
        sql += " ORDER BY #{@order_clauses.join(', ')}" if @order_clauses.any?

        # Add LIMIT and OFFSET (OFFSET requires LIMIT in SQLite)
        if @offset_clause && !@limit_clause
          # SQLite requires LIMIT when using OFFSET, use -1 for unlimited
          sql += " LIMIT -1 #{@offset_clause}"
        elsif @limit_clause
          sql += " #{@limit_clause}"
          sql += " #{@offset_clause}" if @offset_clause
        end

        # Log and execute query
        start_time = Time.now
        SmartSuite::Logger.db_query(sql, @params)

        result = @cache.db.execute(sql, @params)

        duration = Time.now - start_time
        SmartSuite::Logger.db_result(result.length, duration)

        # Map transliterated column names back to original field slugs
        map_column_names_to_field_slugs(result, schema["field_mapping"])
      rescue StandardError => e
        SmartSuite::Logger.error("Cache Query Execute", error: e)
        raise
      end

      # Count results without fetching them
      #
      # @return [Integer] Number of matching records
      def count
        schema = @cache.get_cached_table_schema(@table_id)
        return 0 unless schema

        sql_table_name = schema["sql_table_name"]

        # Build SQL query
        sql = "SELECT COUNT(*) as count FROM #{sql_table_name}"

        # Add WHERE clauses
        sql += " WHERE #{@where_clauses.join(' AND ')}" if @where_clauses.any?

        # Log and execute query
        start_time = Time.now
        SmartSuite::Logger.db_query(sql, @params)

        result = @cache.db.execute(sql, @params).first

        duration = Time.now - start_time
        count = result ? result["count"] : 0
        SmartSuite::Logger.db_result(1, duration) # COUNT always returns 1 row

        count
      rescue StandardError => e
        SmartSuite::Logger.error("Cache Query Count", error: e)
        raise
      end

      private

      # Map transliterated column names back to original SmartSuite field slugs
      #
      # For date fields with include_time metadata, creates a hash structure:
      #   {date: "2025-01-15T10:30:00Z", include_time: true}
      #
      # @param results [Array<Hash>] Query results with transliterated column names
      # @param field_mapping [Hash] Mapping of field_slug => {column_name => type}
      # @return [Array<Hash>] Results with original field slugs as keys
      def map_column_names_to_field_slugs(results, field_mapping)
        # Build reverse mapping: {column_name => field_slug}
        # Also track which columns are _include_time columns
        reverse_mapping = {}
        include_time_columns = {}

        field_mapping.each do |field_slug, columns|
          columns.each_key do |col_name|
            if col_name.end_with?("_include_time")
              # Store include_time column reference: col_name => base_column_name
              base_col = col_name.sub(/_include_time$/, "")
              include_time_columns[col_name] = base_col
            end
            reverse_mapping[col_name] = field_slug
          end
        end

        # Transform each result row
        # rubocop:disable Metrics/BlockLength
        results.map do |row|
          mapped_row = {}
          include_time_values = {} # Temporary storage for include_time values keyed by base_col
          date_column_values = {} # Store date column values keyed by column name
          multi_column_fields = {} # Track fields with from/to structure

          row.each do |col_name, value|
            if include_time_columns.key?(col_name)
              # Store include_time value keyed by base column name
              base_col = include_time_columns[col_name]
              include_time_values[base_col] = [ 1, true ].include?(value)
            else
              # Store the raw value keyed by column name for later processing
              date_column_values[col_name] = value

              # Map column name to original field slug (or keep column name if no mapping)
              field_slug = reverse_mapping[col_name] || col_name

              # Check if this is a multi-column date field (from/to structure)
              if col_name.end_with?("_from")
                multi_column_fields[field_slug] ||= {}
                multi_column_fields[field_slug][:from_col] = col_name
              elsif col_name.end_with?("_to")
                multi_column_fields[field_slug] ||= {}
                multi_column_fields[field_slug][:to_col] = col_name
              elsif col_name.end_with?("_is_overdue")
                multi_column_fields[field_slug] ||= {}
                multi_column_fields[field_slug][:is_overdue] = value == 1
              elsif col_name.end_with?("_is_completed")
                multi_column_fields[field_slug] ||= {}
                multi_column_fields[field_slug][:is_completed] = value == 1
              else
                # For fields with multiple columns (e.g., status has status + status_updated_on),
                # prefer the first column value (don't overwrite)
                mapped_row[field_slug] ||= value
              end
            end
          end

          # Build composite structures for multi-column date fields
          multi_column_fields.each do |field_slug, cols|
            result = {}

            if cols[:from_col]
              from_date = date_column_values[cols[:from_col]]
              from_include_time = include_time_values[cols[:from_col]]
              result["from_date"] = { "date" => from_date, "include_time" => from_include_time || false } if from_date
            end

            if cols[:to_col]
              to_date = date_column_values[cols[:to_col]]
              to_include_time = include_time_values[cols[:to_col]]
              result["to_date"] = { "date" => to_date, "include_time" => to_include_time || false } if to_date
            end

            result["is_overdue"] = cols[:is_overdue] if cols.key?(:is_overdue)
            result["is_completed"] = cols[:is_completed] if cols.key?(:is_completed)

            mapped_row[field_slug] = result unless result.empty?
          end

          # Combine simple date values with their include_time flags
          # Track which field_slugs have been processed to avoid nested hash issue
          processed_fields = Set.new(multi_column_fields.keys)

          include_time_values.each do |base_col, include_time|
            field_slug = reverse_mapping[base_col]
            next unless field_slug
            next if processed_fields.include?(field_slug) # Skip multi-column fields

            # Get the date value from the original column
            date_value = date_column_values[base_col]
            next if date_value.nil?

            # Mark as processed before modifying
            processed_fields.add(field_slug)

            # Create hash with date and include_time flag
            mapped_row[field_slug] = { "date" => date_value, "include_time" => include_time }
          end

          mapped_row
        end
        # rubocop:enable Metrics/BlockLength
      end

      # Build SQL condition for a field
      #
      # @param field_info [Hash] Field definition
      # @param columns [Hash] Column name => type mapping
      # @param condition [Object] Condition value or hash
      # @param full_field_slug [String] Full field slug including .from_date/.to_date suffix (optional)
      # @return [Array<String, Array>] [SQL clause, parameters]
      def build_condition(field_info, columns, condition, full_field_slug = nil)
        field_type = field_info["field_type"].downcase
        # Use full_field_slug if provided, otherwise fall back to field_info slug
        field_slug = full_field_slug || field_info["slug"]

        # Select appropriate column based on field type and slug
        # For duedatefield and daterangefield, SmartSuite API uses to_date for all comparisons
        # unless explicitly filtering by .from_date or .to_date sub-field
        col_name = if %w[duedatefield daterangefield].include?(field_type)
                     # Check if filtering by sub-field (e.g., due_date.from_date)
                     if field_slug.end_with?(".from_date")
                       # User explicitly requested from_date column
                       columns.keys.find { |k| k.end_with?("_from") } || columns.keys.first
                     elsif field_slug.end_with?(".to_date")
                       # User explicitly requested to_date column
                       columns.keys.find { |k| k.end_with?("_to") } || columns.keys.first
                     else
                       # Default: use to_date column (matches SmartSuite API behavior)
                       columns.keys.find { |k| k.end_with?("_to") } || columns.keys.first
                     end
        else
                     # For other field types, use first column
                     columns.keys.first
        end

        # Handle different condition formats
        if condition.is_a?(Hash)
          # Complex condition: {operator => value}
          build_complex_condition(field_type, col_name, condition)
        else
          # Simple equality
          [ "#{col_name} = ?", [ condition ] ]
        end
      end

      # Build complex condition with operators
      #
      # @param field_type [String] SmartSuite field type
      # @param col_name [String] SQL column name
      # @param condition [Hash] {operator => value}
      # @return [Array<String, Array>] [SQL clause, parameters]
      def build_complex_condition(field_type, col_name, condition)
        operator, value = condition.first

        case operator
        when :eq
          [ "#{col_name} = ?", [ value ] ]
        when :ne, :not_eq
          [ "#{col_name} != ?", [ value ] ]
        when :gt
          [ "#{col_name} > ?", [ value ] ]
        when :gte
          [ "#{col_name} >= ?", [ value ] ]
        when :lt
          [ "#{col_name} < ?", [ value ] ]
        when :lte
          [ "#{col_name} <= ?", [ value ] ]
        when :contains
          if json_array_field?(field_type)
            # For JSON array fields (linked records, multi-select, etc.):
            # Search within JSON array using json_extract
            # NOTE: For linked records, this searches record IDs, not display values.
            # SmartSuite API's `contains` searches display fields, but cache layer
            # only has IDs. Use `has_any_of` with record IDs for exact matching.
            [ "json_extract(#{col_name}, '$') LIKE ?", [ "%#{value}%" ] ]
          else
            # For text fields: standard case-insensitive LIKE search
            [ "#{col_name} LIKE ?", [ "%#{value}%" ] ]
          end
        when :starts_with
          [ "#{col_name} LIKE ?", [ "#{value}%" ] ]
        when :ends_with
          [ "#{col_name} LIKE ?", [ "%#{value}" ] ]
        when :in, :is_any_of
          placeholders = value.map { "?" }.join(",")
          [ "#{col_name} IN (#{placeholders})", value ]
        when :not_in, :is_none_of
          placeholders = value.map { "?" }.join(",")
          [ "#{col_name} NOT IN (#{placeholders})", value ]
        when :between
          [ "#{col_name} BETWEEN ? AND ?", [ value[:min], value[:max] ] ]
        when :not_between
          # Date is NOT within the range (for "is_not" on date fields)
          [ "(#{col_name} < ? OR #{col_name} > ?)", [ value[:min], value[:max] ] ]
        when :is_null
          [ "#{col_name} IS NULL", [] ]
        when :is_not_null
          [ "#{col_name} IS NOT NULL", [] ]
        when :is_empty
          # For JSON array fields (userfield, multipleselectfield, linkedrecordfield)
          if json_array_field?(field_type)
            [ "(#{col_name} IS NULL OR #{col_name} = '[]')", [] ]
          # For text fields
          elsif text_field?(field_type)
            [ "(#{col_name} IS NULL OR #{col_name} = '')", [] ]
          else
            [ "#{col_name} IS NULL", [] ]
          end
        when :is_not_empty
          # For JSON array fields (userfield, multipleselectfield, linkedrecordfield)
          if json_array_field?(field_type)
            [ "(#{col_name} IS NOT NULL AND #{col_name} != '[]')", [] ]
          # For text fields
          elsif text_field?(field_type)
            [ "(#{col_name} IS NOT NULL AND #{col_name} != '')", [] ]
          else
            [ "#{col_name} IS NOT NULL", [] ]
          end
        when :has_any_of
          # For JSON arrays (assigned_to, linked_record, tags, etc.)
          conditions = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          [ "(#{conditions.join(' OR ')})", params ]
        when :has_all_of
          # All values must be present in JSON array
          conditions = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          [ "(#{conditions.join(' AND ')})", params ]
        when :has_none_of
          # None of the values should be present
          conditions = value.map { "json_extract(#{col_name}, '$') NOT LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          [ "(#{conditions.join(' AND ')})", params ]
        when :is_exactly
          # Array must contain exactly these values (no more, no less)
          # Check: (1) length matches AND (2) all values present
          length_check = "json_array_length(#{col_name}) = ?"
          value_checks = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          all_conditions = [ length_check ] + value_checks
          params = [ value.length ] + value.map { |v| "%\"#{v}\"%" }
          [ "(#{all_conditions.join(' AND ')})", params ]

        # Date comparison operators
        # These work with date-only strings (YYYY-MM-DD) or ISO timestamps
        when :is_before
          [ "#{col_name} < ?", [ value ] ]
        when :is_after
          [ "#{col_name} > ?", [ value ] ]
        when :is_on_or_before
          [ "#{col_name} <= ?", [ value ] ]
        when :is_on_or_after
          [ "#{col_name} >= ?", [ value ] ]

        # Due Date special operators (duedatefield only)
        # Uses the cached is_overdue flag from SmartSuite API.
        # Note: SmartSuite's overdue logic is complex - it considers if completion
        # happened after the due date, not just current completion status.
        # Refresh cache to get updated is_overdue values.
        when :is_overdue
          # Derive the is_overdue column name from the date column
          # e.g., "due_date_to" -> "due_date_is_overdue"
          is_overdue_col = col_name.sub(/_(?:to|from)$/, "") + "_is_overdue"
          [ "#{is_overdue_col} = 1", [] ]
        when :is_not_overdue
          is_overdue_col = col_name.sub(/_(?:to|from)$/, "") + "_is_overdue"
          [ "(#{is_overdue_col} = 0 OR #{is_overdue_col} IS NULL)", [] ]

        # File field operators (filefield only)
        # Files are stored as JSON array: [{"name": "file.pdf", "type": "pdf", ...}, ...]
        when :file_name_contains
          # Search for filename in JSON array
          [ "#{col_name} LIKE ?", [ "%\"name\":%#{value}%" ] ]
        when :file_type_is
          # Search for file type in JSON array
          # Valid types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
          [ "#{col_name} LIKE ?", [ "%\"type\":\"#{value}\"%" ] ]

        else
          # Fallback: treat as equality
          [ "#{col_name} = ?", [ value ] ]
        end
      end
    end
  end
end
