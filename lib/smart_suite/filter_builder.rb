# frozen_string_literal: true

require "time"
require_relative "date_formatter"
require_relative "date_mode_resolver"
require_relative "filter_validator"

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
    # Supports nested AND/OR filter groups for complex queries.
    #
    # @param query [SmartSuite::Cache::Query] Cache query builder instance
    # @param filter [Hash] SmartSuite filter hash with 'operator' and 'fields' keys
    # @return [SmartSuite::Cache::Query] Query with filters applied
    # @example Simple filter
    #   filter = {"operator" => "and", "fields" => [{"field" => "status", "comparison" => "is", "value" => "Active"}]}
    #   query = FilterBuilder.apply_to_query(cache.query(table_id), filter)
    #   results = query.execute
    #
    # @example Nested filter with OR
    #   filter = {
    #     "operator" => "or",
    #     "fields" => [
    #       {"operator" => "and", "fields" => [
    #         {"field" => "status", "comparison" => "is", "value" => "active"},
    #         {"field" => "priority", "comparison" => "is", "value" => "high"}
    #       ]},
    #       {"field" => "overdue", "comparison" => "is", "value" => true}
    #     ]
    #   }
    def self.apply_to_query(query, filter)
      return query unless filter && filter["fields"]

      # Check if this filter has nested groups (items with their own operator/fields)
      has_nested = filter["fields"].any? { |f| f["operator"] && f["fields"] }
      filter_operator = (filter["operator"] || "and").downcase

      if has_nested || filter_operator == "or"
        # Build a composite SQL clause for the entire filter group
        clause, params = build_filter_group_sql(query, filter)
        query = query.where_raw(clause, params) if clause && !clause.empty?
      else
        # Simple flat AND filter - use efficient where() chaining
        filter["fields"].each do |field_filter|
          field_slug = field_filter["field"]
          comparison = field_filter["comparison"]
          value = field_filter["value"]

          # Validate operator is compatible with field type
          validate_filter_operator(query, field_slug, comparison)

          # Convert SmartSuite comparison operator to cache query condition
          condition = convert_comparison(comparison, value)

          # Apply filter to query
          query = query.where(field_slug.to_sym => condition)
        end
      end

      query
    end

    # Build SQL clause for a filter group (supports nested AND/OR logic)
    #
    # @param query [SmartSuite::Cache::Query] Query instance for building SQL
    # @param filter [Hash] Filter group with 'operator' and 'fields'
    # @return [Array<String, Array>] [sql_clause, params]
    def self.build_filter_group_sql(query, filter)
      return [ nil, [] ] unless filter && filter["fields"]

      operator = (filter["operator"] || "and").upcase
      clauses = []
      all_params = []

      filter["fields"].each do |field_filter|
        if field_filter["operator"] && field_filter["fields"]
          # Nested group - recurse
          nested_clause, nested_params = build_filter_group_sql(query, field_filter)
          if nested_clause && !nested_clause.empty?
            clauses << "(#{nested_clause})"
            all_params.concat(nested_params)
          end
        else
          # Leaf condition
          field_slug = field_filter["field"]
          comparison = field_filter["comparison"]
          value = field_filter["value"]

          # Validate operator is compatible with field type
          validate_filter_operator(query, field_slug, comparison)

          # Convert to cache query format
          condition = convert_comparison(comparison, value)

          # Build SQL using query's method
          clause, params = query.build_condition_sql(field_slug.to_sym, condition)
          if clause
            clauses << clause
            all_params.concat(params)
          end
        end
      end

      return [ nil, [] ] if clauses.empty?

      # Join clauses with the appropriate operator
      combined = clauses.join(" #{operator} ")
      [ combined, all_params ]
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
      when "is", "is_equal_to"
        # Check if this is a date-only value that needs range conversion
        date_range = convert_date_to_range(value)
        return date_range if date_range

        value
      when "is_not", "is_not_equal_to"
        # Check if this is a date-only value that needs NOT IN range conversion
        date_not_range = convert_date_to_not_range(value)
        return date_not_range if date_not_range

        { ne: value }

      # Numeric comparison operators
      when "is_greater_than"
        { gt: value }
      when "is_less_than"
        { lt: value }
      when "is_equal_or_greater_than"
        { gte: value }
      when "is_equal_or_less_than"
        { lte: value }

      # Text operators
      when "contains"
        { contains: value }
      when "not_contains", "does_not_contain"
        { not_contains: value }

      # Null check operators
      when "is_empty"
        { is_empty: true }
      when "is_not_empty"
        { is_not_empty: true }

      # Array operators (multi-select, linked records, tags)
      when "has_any_of"
        { has_any_of: value }
      when "has_all_of"
        { has_all_of: value }
      when "is_exactly"
        { is_exactly: value }
      when "has_none_of"
        { has_none_of: value }

      # Single select array operators (matches any/none of the values)
      when "is_any_of"
        { is_any_of: Array(value) }
      when "is_none_of"
        { is_none_of: Array(value) }

      # Date operators - preserve operator type and extract date value
      # These need special handling in postgres_layer for date field accessors
      when "is_before"
        { is_before: extract_date_value(value) }
      when "is_on_or_before"
        { is_on_or_before: extract_date_value(value) }
      when "is_on_or_after"
        { is_on_or_after: extract_date_value(value) }

      # Due Date special operators (duedatefield only)
      when "is_overdue"
        { is_overdue: true }
      when "is_not_overdue"
        { is_not_overdue: true }

      # File field operators (filefield only)
      when "file_name_contains"
        { file_name_contains: value }
      when "file_type_is"
        { file_type_is: value }

      # Default: equality
      else
        value
      end
    end

    # Extract date value from SmartSuite date object format and convert to UTC.
    #
    # SmartSuite date filters can come in several formats:
    # 1. Simple string: "2025-01-01"
    # 2. Date object with exact date: {"date_mode" => "exact_date", "date_mode_value" => "2025-01-01"}
    # 3. Date object with dynamic mode: {"date_mode" => "today"} (no date_mode_value)
    #
    # For date-only values (no time component), the date represents a calendar day
    # in the user's local timezone. This method converts it to a UTC timestamp
    # that corresponds to the start of that day in the local timezone.
    #
    # @param value [String, Hash] Date value (simple string or nested hash)
    # @return [String] UTC timestamp string (ISO 8601 format)
    # @example Date-only input (assumes -0700 timezone)
    #   extract_date_value("2025-06-15")
    #   #=> "2025-06-15T07:00:00Z" (midnight local = 7am UTC)
    # @example With time already specified
    #   extract_date_value("2025-06-15T14:30:00Z")
    #   #=> "2025-06-15T14:30:00Z" (unchanged)
    # @example Dynamic date mode
    #   extract_date_value({"date_mode" => "today"})
    #   #=> "2025-12-13T08:00:00Z" (today's date in UTC)
    def self.extract_date_value(value)
      return nil if value.nil?

      # Use DateModeResolver to handle all date value formats including dynamic modes
      date_str = SmartSuite::DateModeResolver.extract_date_value(value)

      convert_to_utc_for_filter(date_str)
    end

    # Convert a date string to UTC for cache filtering.
    #
    # For date-only values, converts to the start of day in local timezone expressed as UTC.
    # For datetime values, returns as-is (already in UTC format).
    #
    # @param date_str [String] Date or datetime string
    # @return [String] UTC timestamp
    def self.convert_to_utc_for_filter(date_str)
      return date_str unless date_str.is_a?(String)

      # Check if it's a date-only format (YYYY-MM-DD)
      if date_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        # Get the timezone offset for the specific date (handles DST correctly)
        offset = local_timezone_offset(date_str)
        # Convert local midnight to UTC
        # e.g., 2026-06-15 00:00:00 -0700 = 2026-06-15T07:00:00Z
        local_time = Time.parse("#{date_str}T00:00:00#{offset}")
        local_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      else
        # Already has time component, return as-is
        date_str
      end
    end

    # Convert a date-only value to a range condition for "is" operator.
    #
    # SmartSuite stores date-only fields as UTC timestamps (e.g., "2025-06-05T00:00:00Z").
    # This method converts a date-only filter value to a range that covers the entire day
    # in UTC to match stored timestamps.
    #
    # @param value [String, Hash] Date value (simple string or nested hash with date_mode_value)
    # @return [Hash, nil] Range condition {between: {min:, max:}} or nil if not a date-only value
    # @example
    #   convert_date_to_range("2026-06-15")
    #   #=> {between: {min: "2026-06-15T00:00:00Z", max: "2026-06-15T23:59:59Z"}}
    def self.convert_date_to_range(value)
      # Extract date string from nested hash if needed
      date_str = if value.is_a?(Hash) && value["date_mode_value"]
                   value["date_mode_value"]
      elsif value.is_a?(String)
                   value
      end

      return nil unless date_str.is_a?(String)

      # Only convert date-only format (YYYY-MM-DD)
      return nil unless date_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      # SmartSuite stores date-only fields as UTC timestamps at midnight.
      # Use a range covering the entire day to match any time on that date.
      { between: { min: "#{date_str}T00:00:00Z", max: "#{date_str}T23:59:59Z" } }
    end

    # Convert a date-only value to a NOT IN range condition for "is_not" operator.
    #
    # SmartSuite stores date-only fields as UTC timestamps (e.g., "2025-06-05T00:00:00Z").
    # This method converts a date-only filter value to exclude the entire day in UTC.
    #
    # @param value [String, Hash] Date value (simple string or nested hash with date_mode_value)
    # @return [Hash, nil] Not-range condition {not_between: {min:, max:}} or nil if not a date-only value
    # @example
    #   convert_date_to_not_range("2026-06-15")
    #   #=> {not_between: {min: "2026-06-15T00:00:00Z", max: "2026-06-15T23:59:59Z"}}
    def self.convert_date_to_not_range(value)
      # Extract date string from nested hash if needed
      date_str = if value.is_a?(Hash) && value["date_mode_value"]
                   value["date_mode_value"]
      elsif value.is_a?(String)
                   value
      end

      return nil unless date_str.is_a?(String)

      # Only convert date-only format (YYYY-MM-DD)
      return nil unless date_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      # SmartSuite stores date-only fields as UTC timestamps.
      # Use a range covering the entire day to exclude any time on that date.
      { not_between: { min: "#{date_str}T00:00:00Z", max: "#{date_str}T23:59:59Z" } }
    end

    # Validate that a filter operator is compatible with the field type.
    #
    # Uses the query's schema to look up the field type and validates the operator.
    # Logs a warning if the operator is invalid (non-strict mode by default).
    #
    # @param query [SmartSuite::Cache::Query] Query instance with schema access
    # @param field_slug [String] Field identifier
    # @param operator [String] Filter comparison operator
    # @return [Boolean] true if valid, false otherwise
    def self.validate_filter_operator(query, field_slug, operator)
      return true unless query.respond_to?(:get_field_type)

      field_type = query.get_field_type(field_slug)
      return true if field_type.nil? # Can't validate without field type info

      FilterValidator.validate!(field_slug, operator, field_type, strict: false)
    end

    # Get the local timezone offset string for the configured timezone.
    #
    # When a reference_date is provided, calculates the offset for that specific date.
    # This is important for proper DST handling - a date in July might have a different
    # offset than a date in January for the same timezone.
    #
    # @param reference_date [String, nil] Date string (YYYY-MM-DD) to calculate offset for
    # @return [String] Timezone offset (e.g., "-0700", "+0530")
    def self.local_timezone_offset(reference_date = nil)
      eff_tz = DateFormatter.effective_timezone

      # Helper to get offset for a specific time
      get_offset_for_time = lambda do |time_to_check|
        time_to_check.strftime("%z")
      end

      # Parse reference date or use current time
      ref_time = if reference_date&.match?(/\A\d{4}-\d{2}-\d{2}\z/)
                   Time.parse("#{reference_date}T12:00:00") # Use noon to avoid edge cases
      else
                   Time.now
      end

      if eff_tz == :utc
        "+0000"
      elsif eff_tz.nil?
        # Use system timezone for the reference date
        get_offset_for_time.call(ref_time)
      elsif eff_tz.match?(/\A[+-]\d{4}\z/)
        # Already in offset format (no DST adjustment possible)
        eff_tz
      elsif eff_tz.match?(%r{\A[A-Za-z]+/[A-Za-z_]+})
        # Named timezone - temporarily set TZ to get offset for reference date
        original_tz = ENV.fetch("TZ", nil)
        begin
          ENV["TZ"] = eff_tz
          # Re-parse time with new TZ to get correct offset
          ref_time_in_tz = Time.parse("#{reference_date || Time.now.strftime('%Y-%m-%d')}T12:00:00")
          get_offset_for_time.call(ref_time_in_tz)
        ensure
          if original_tz
            ENV["TZ"] = original_tz
          else
            ENV.delete("TZ")
          end
        end
      else
        # Fallback to system timezone
        get_offset_for_time.call(ref_time)
      end
    end
  end
end
