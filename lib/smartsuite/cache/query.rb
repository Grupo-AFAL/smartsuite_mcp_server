# frozen_string_literal: true

require_relative '../../query_logger'

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

        field_mapping = schema['field_mapping']
        structure = schema['structure']
        fields_info = structure['structure'] || []

        conditions.each do |field_slug, condition|
          # Find field info
          field_info = fields_info.find { |f| f['slug'] == field_slug.to_s }
          next unless field_info # Skip unknown fields

          # Get SQL column name(s)
          columns = field_mapping[field_slug.to_s]
          next unless columns

          # Build condition
          clause, params = build_condition(field_info, columns, condition)
          @where_clauses << clause
          @params.concat(params)
        end

        self
      end

      # Add ORDER BY clause
      #
      # Can be called multiple times to add additional sort criteria.
      #
      # @param field_slug [String, Symbol] Field to order by
      # @param direction [String] 'ASC' or 'DESC'
      # @return [CacheQuery] self for chaining
      def order(field_slug, direction = 'ASC')
        schema = @cache.get_cached_table_schema(@table_id)
        return self unless schema

        field_mapping = schema['field_mapping']
        structure = schema['structure']
        fields_info = structure['structure'] || []

        columns = field_mapping[field_slug.to_s]

        if columns
          # Find field info to check field type
          field_info = fields_info.find { |f| f['slug'] == field_slug.to_s }
          field_type = field_info ? field_info['field_type'].downcase : nil

          # Select appropriate column based on field type (same logic as build_condition)
          # For duedatefield and daterangefield, SmartSuite API uses to_date for sorting
          col_name = if %w[duedatefield daterangefield].include?(field_type)
                       # Check if sorting by sub-field (e.g., due_date.from_date)
                       if field_slug.to_s.end_with?('.from_date')
                         columns.keys.find { |k| k.end_with?('_from') } || columns.keys.first
                       elsif field_slug.to_s.end_with?('.to_date')
                         columns.keys.find { |k| k.end_with?('_to') } || columns.keys.first
                       else
                         # Default: use to_date column (matches SmartSuite API behavior)
                         columns.keys.find { |k| k.end_with?('_to') } || columns.keys.first
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

        sql_table_name = schema['sql_table_name']

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
        QueryLogger.log_db_query(sql, @params)

        result = @cache.db.execute(sql, @params)

        duration = Time.now - start_time
        QueryLogger.log_db_result(result.length, duration)

        # Map transliterated column names back to original field slugs
        map_column_names_to_field_slugs(result, schema['field_mapping'])
      rescue StandardError => e
        QueryLogger.log_error('Cache Query Execute', e)
        raise
      end

      # Count results without fetching them
      #
      # @return [Integer] Number of matching records
      def count
        schema = @cache.get_cached_table_schema(@table_id)
        return 0 unless schema

        sql_table_name = schema['sql_table_name']

        # Build SQL query
        sql = "SELECT COUNT(*) as count FROM #{sql_table_name}"

        # Add WHERE clauses
        sql += " WHERE #{@where_clauses.join(' AND ')}" if @where_clauses.any?

        # Log and execute query
        start_time = Time.now
        QueryLogger.log_db_query(sql, @params)

        result = @cache.db.execute(sql, @params).first

        duration = Time.now - start_time
        count = result ? result['count'] : 0
        QueryLogger.log_db_result(1, duration) # COUNT always returns 1 row

        count
      rescue StandardError => e
        QueryLogger.log_error('Cache Query Count', e)
        raise
      end

      private

      # Map transliterated column names back to original SmartSuite field slugs
      #
      # @param results [Array<Hash>] Query results with transliterated column names
      # @param field_mapping [Hash] Mapping of field_slug => {column_name => type}
      # @return [Array<Hash>] Results with original field slugs as keys
      def map_column_names_to_field_slugs(results, field_mapping)
        # Build reverse mapping: {column_name => field_slug}
        reverse_mapping = {}
        field_mapping.each do |field_slug, columns|
          columns.each_key do |col_name|
            reverse_mapping[col_name] = field_slug
          end
        end

        # Transform each result row
        results.map do |row|
          mapped_row = {}
          row.each do |col_name, value|
            # Map column name to original field slug (or keep column name if no mapping)
            field_slug = reverse_mapping[col_name] || col_name

            # For fields with multiple columns (e.g., status has status + status_updated_on),
            # prefer the first column value (don't overwrite)
            mapped_row[field_slug] ||= value
          end
          mapped_row
        end
      end

      # Build SQL condition for a field
      #
      # @param field_info [Hash] Field definition
      # @param columns [Hash] Column name => type mapping
      # @param condition [Object] Condition value or hash
      # @return [Array<String, Array>] [SQL clause, parameters]
      def build_condition(field_info, columns, condition)
        field_type = field_info['field_type'].downcase
        field_slug = field_info['slug']

        # Select appropriate column based on field type and slug
        # For duedatefield and daterangefield, SmartSuite API uses to_date for all comparisons
        # unless explicitly filtering by .from_date or .to_date sub-field
        col_name = if %w[duedatefield daterangefield].include?(field_type)
                     # Check if filtering by sub-field (e.g., due_date.from_date)
                     if field_slug.end_with?('.from_date')
                       # User explicitly requested from_date column
                       columns.keys.find { |k| k.end_with?('_from') } || columns.keys.first
                     elsif field_slug.end_with?('.to_date')
                       # User explicitly requested to_date column
                       columns.keys.find { |k| k.end_with?('_to') } || columns.keys.first
                     else
                       # Default: use to_date column (matches SmartSuite API behavior)
                       columns.keys.find { |k| k.end_with?('_to') } || columns.keys.first
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
          ["#{col_name} = ?", [condition]]
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
          ["#{col_name} = ?", [value]]
        when :ne, :not_eq
          ["#{col_name} != ?", [value]]
        when :gt
          ["#{col_name} > ?", [value]]
        when :gte
          ["#{col_name} >= ?", [value]]
        when :lt
          ["#{col_name} < ?", [value]]
        when :lte
          ["#{col_name} <= ?", [value]]
        when :contains
          ["#{col_name} LIKE ?", ["%#{value}%"]]
        when :starts_with
          ["#{col_name} LIKE ?", ["#{value}%"]]
        when :ends_with
          ["#{col_name} LIKE ?", ["%#{value}"]]
        when :in
          placeholders = value.map { '?' }.join(',')
          ["#{col_name} IN (#{placeholders})", value]
        when :not_in
          placeholders = value.map { '?' }.join(',')
          ["#{col_name} NOT IN (#{placeholders})", value]
        when :between
          ["#{col_name} BETWEEN ? AND ?", [value[:min], value[:max]]]
        when :is_null
          ["#{col_name} IS NULL", []]
        when :is_not_null
          ["#{col_name} IS NOT NULL", []]
        when :is_empty
          # For JSON array fields (userfield, multipleselectfield, linkedrecordfield)
          if json_array_field?(field_type)
            ["(#{col_name} IS NULL OR #{col_name} = '[]')", []]
          # For text fields
          elsif text_field?(field_type)
            ["(#{col_name} IS NULL OR #{col_name} = '')", []]
          else
            ["#{col_name} IS NULL", []]
          end
        when :is_not_empty
          # For JSON array fields (userfield, multipleselectfield, linkedrecordfield)
          if json_array_field?(field_type)
            ["(#{col_name} IS NOT NULL AND #{col_name} != '[]')", []]
          # For text fields
          elsif text_field?(field_type)
            ["(#{col_name} IS NOT NULL AND #{col_name} != '')", []]
          else
            ["#{col_name} IS NOT NULL", []]
          end
        when :has_any_of
          # For JSON arrays (assigned_to, linked_record, tags, etc.)
          conditions = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          ["(#{conditions.join(' OR ')})", params]
        when :has_all_of
          # All values must be present in JSON array
          conditions = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          ["(#{conditions.join(' AND ')})", params]
        when :has_none_of
          # None of the values should be present
          conditions = value.map { "json_extract(#{col_name}, '$') NOT LIKE ?" }
          params = value.map { |v| "%\"#{v}\"%" }
          ["(#{conditions.join(' AND ')})", params]
        when :is_exactly
          # Array must contain exactly these values (no more, no less)
          # Check: (1) length matches AND (2) all values present
          length_check = "json_array_length(#{col_name}) = ?"
          value_checks = value.map { "json_extract(#{col_name}, '$') LIKE ?" }
          all_conditions = [length_check] + value_checks
          params = [value.length] + value.map { |v| "%\"#{v}\"%" }
          ["(#{all_conditions.join(' AND ')})", params]
        else
          # Fallback: treat as equality
          ["#{col_name} = ?", [value]]
        end
      end
    end
  end
end
