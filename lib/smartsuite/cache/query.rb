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

      def initialize(cache, table_id)
        @cache = cache
        @table_id = table_id
        @where_clauses = []
        @params = []
        @order_clause = nil
        @limit_clause = nil
        @offset_clause = nil
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
      # @param field_slug [String, Symbol] Field to order by
      # @param direction [String] 'ASC' or 'DESC'
      # @return [CacheQuery] self for chaining
      def order(field_slug, direction = 'ASC')
        schema = @cache.get_cached_table_schema(@table_id)
        return self unless schema

        field_mapping = schema['field_mapping']
        columns = field_mapping[field_slug.to_s]

        if columns
          # Use first column for ordering
          col_name = columns.keys.first
          @order_clause = "ORDER BY #{col_name} #{direction.upcase}"
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
      # @return [Array<Hash>] Query results
      def execute
        schema = @cache.get_cached_table_schema(@table_id)
        return [] unless schema

        sql_table_name = schema['sql_table_name']

        # Build SQL query
        sql = "SELECT * FROM #{sql_table_name}"

        # Add WHERE clauses
        sql += " WHERE #{@where_clauses.join(' AND ')}" if @where_clauses.any?

        # Add ORDER BY
        sql += " #{@order_clause}" if @order_clause

        # Add LIMIT and OFFSET
        sql += " #{@limit_clause}" if @limit_clause
        sql += " #{@offset_clause}" if @offset_clause

        # Log and execute query
        start_time = Time.now
        QueryLogger.log_db_query(sql, @params)

        result = @cache.db.execute(sql, @params)

        duration = Time.now - start_time
        QueryLogger.log_db_result(result.length, duration)

        result
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

      # Build SQL condition for a field
      #
      # @param field_info [Hash] Field definition
      # @param columns [Hash] Column name => type mapping
      # @param condition [Object] Condition value or hash
      # @return [Array<String, Array>] [SQL clause, parameters]
      def build_condition(field_info, columns, condition)
        field_type = field_info['field_type'].downcase
        col_name = columns.keys.first # Primary column

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
          # For text fields
          if field_type =~ /text|email|phone|link/
            ["(#{col_name} IS NULL OR #{col_name} = '')", []]
          else
            ["#{col_name} IS NULL", []]
          end
        when :is_not_empty
          # For text fields
          if field_type =~ /text|email|phone|link/
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
        else
          # Fallback: treat as equality
          ["#{col_name} = ?", [value]]
        end
      end
    end
  end
end
