# frozen_string_literal: true

module SmartSuite
  # FilterBuilder converts SmartSuite API filter syntax to cache query conditions.
  #
  # This module provides utilities for translating SmartSuite's filter format
  # (used in API requests) to the format expected by the cache layer's query builder.
  #
  # SmartSuite filter format:
  #   {
  #     "operator": "and",
  #     "fields": [
  #       {"field": "status", "comparison": "is", "value": "Active"},
  #       {"field": "priority", "comparison": "is_greater_than", "value": 3}
  #     ]
  #   }
  #
  # Cache query format:
  #   query.where(status: "Active").where(priority: {gt: 3})
  #
  # @example Basic usage
  #   filter = {"operator" => "and", "fields" => [{"field" => "status", "comparison" => "is", "value" => "Active"}]}
  #   query = SmartSuite::FilterBuilder.apply_to_query(query, filter)
  #
  # @example Supported operators
  #   FilterBuilder.convert_comparison("is", "Active")           #=> "Active"
  #   FilterBuilder.convert_comparison("is_greater_than", 5)     #=> {gt: 5}
  #   FilterBuilder.convert_comparison("contains", "test")       #=> {contains: "test"}
  #   FilterBuilder.convert_comparison("has_any_of", ["a", "b"]) #=> {has_any_of: ["a", "b"]}
  module FilterBuilder
    # Apply SmartSuite filter criteria to a cache query.
    #
    # Iterates through filter fields and applies each condition to the query builder.
    # Handles conversion from SmartSuite comparison operators to cache query format.
    #
    # @param query [SmartSuite::Cache::Query] Cache query builder instance
    # @param filter [Hash] SmartSuite filter hash with 'operator' and 'fields' keys
    # @return [SmartSuite::Cache::Query] Query with filters applied
    # @example
    #   filter = {"operator" => "and", "fields" => [{"field" => "status", "comparison" => "is", "value" => "Active"}]}
    #   query = FilterBuilder.apply_to_query(cache.query(table_id), filter)
    #   results = query.execute
    def self.apply_to_query(query, filter)
      return query unless filter && filter['fields']

      filter['fields'].each do |field_filter|
        field_slug = field_filter['field']
        comparison = field_filter['comparison']
        value = field_filter['value']

        # Convert SmartSuite comparison operator to cache query condition
        condition = convert_comparison(comparison, value)

        # Apply filter to query
        query = query.where(field_slug.to_sym => condition)
      end

      query
    end

    # Convert SmartSuite comparison operator to cache query condition format.
    #
    # Maps SmartSuite filter operators to the hash format expected by the cache query builder.
    # Supports all SmartSuite comparison operators including text, numeric, date, and array comparisons.
    #
    # @param comparison [String] SmartSuite comparison operator
    # @param value [Object] Filter value (String, Integer, Array, Hash, etc.)
    # @return [Object] Condition in cache query format (value or hash with operator key)
    #
    # @example Equality operators
    #   convert_comparison("is", "Active")            #=> "Active"
    #   convert_comparison("is_not", "Inactive")      #=> {ne: "Inactive"}
    #
    # @example Numeric operators
    #   convert_comparison("is_greater_than", 5)      #=> {gt: 5}
    #   convert_comparison("is_less_than", 10)        #=> {lt: 10}
    #   convert_comparison("is_equal_or_greater_than", 5)  #=> {gte: 5}
    #   convert_comparison("is_equal_or_less_than", 10)    #=> {lte: 10}
    #
    # @example Text operators
    #   convert_comparison("contains", "test")        #=> {contains: "test"}
    #   convert_comparison("not_contains", "spam")    #=> {not_contains: "spam"}
    #
    # @example Null operators
    #   convert_comparison("is_empty", nil)           #=> nil
    #   convert_comparison("is_not_empty", nil)       #=> {is_not_null: true}
    #
    # @example Array operators (for multi-select, linked records, etc.)
    #   convert_comparison("has_any_of", ["a", "b"])  #=> {has_any_of: ["a", "b"]}
    #   convert_comparison("has_all_of", ["a", "b"])  #=> {has_all_of: ["a", "b"]}
    #   convert_comparison("is_exactly", ["a", "b"])  #=> {is_exactly: ["a", "b"]}
    #   convert_comparison("has_none_of", ["a", "b"]) #=> {has_none_of: ["a", "b"]}
    #
    # @example Date operators
    #   convert_comparison("is_before", "2025-01-01") #=> {lt: "2025-01-01"}
    #   convert_comparison("is_after", "2025-01-01")  #=> {gt: "2025-01-01"}
    #   convert_comparison("is_on_or_before", "2025-01-01") #=> {lte: "2025-01-01"}
    #   convert_comparison("is_on_or_after", "2025-01-01")  #=> {gte: "2025-01-01"}
    def self.convert_comparison(comparison, value)
      case comparison
      # Equality operators
      when 'is', 'is_equal_to'
        value
      when 'is_not', 'is_not_equal_to'
        { ne: value }

      # Numeric comparison operators
      when 'is_greater_than'
        { gt: value }
      when 'is_less_than'
        { lt: value }
      when 'is_equal_or_greater_than'
        { gte: value }
      when 'is_equal_or_less_than'
        { lte: value }

      # Text operators
      when 'contains'
        { contains: value }
      when 'not_contains', 'does_not_contain'
        { not_contains: value }

      # Null check operators
      when 'is_empty'
        nil
      when 'is_not_empty'
        { is_not_null: true }

      # Array operators (multi-select, linked records, tags)
      when 'has_any_of'
        { has_any_of: value }
      when 'has_all_of'
        { has_all_of: value }
      when 'is_exactly'
        { is_exactly: value }
      when 'has_none_of'
        { has_none_of: value }

      # Date operators (map to numeric comparisons)
      # Extract actual date value if value is a hash with date_mode_value
      when 'is_before'
        { lt: extract_date_value(value) }
      when 'is_after'
        { gt: extract_date_value(value) }
      when 'is_on_or_before'
        { lte: extract_date_value(value) }
      when 'is_on_or_after'
        { gte: extract_date_value(value) }

      # Default: equality
      else
        value
      end
    end

    # Extract date value from SmartSuite date object format.
    #
    # SmartSuite date filters can come in two formats:
    # 1. Simple string: "2025-01-01"
    # 2. Date object: {"date_mode" => "exact_date", "date_mode_value" => "2025-01-01"}
    #
    # This method normalizes both formats to return the actual date string.
    #
    # @param value [String, Hash] Date value (simple string or nested hash)
    # @return [String] Actual date string
    # @example
    #   extract_date_value("2025-01-01")                                     #=> "2025-01-01"
    #   extract_date_value({"date_mode" => "exact_date", "date_mode_value" => "2025-01-01"}) #=> "2025-01-01"
    def self.extract_date_value(value)
      if value.is_a?(Hash) && value['date_mode_value']
        value['date_mode_value']
      else
        value
      end
    end
  end
end
