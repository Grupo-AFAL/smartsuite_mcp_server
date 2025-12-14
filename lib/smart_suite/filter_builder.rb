# frozen_string_literal: true

require "time"
require_relative "date_formatter"
require_relative "date_mode_resolver"

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
      return query unless filter && filter["fields"]

      filter["fields"].each do |field_filter|
        field_slug = field_filter["field"]
        comparison = field_filter["comparison"]
        value = field_filter["value"]

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
      when "is", "is_equal_to"
        # Check if this is a date-only value that needs range conversion
        date_range = convert_date_to_range(value)
        return date_range if date_range

        value
      when "is_not", "is_not_equal_to"
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

      # Date operators - preserve operator type and extract date value
      # These need special handling in postgres_layer for date field accessors
      when "is_before"
        { is_before: extract_date_value(value) }
      when "is_after"
        { is_after: extract_date_value(value) }
      when "is_on_or_before"
        { is_on_or_before: extract_date_value(value) }
      when "is_on_or_after"
        { is_on_or_after: extract_date_value(value) }

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
    # When filtering with "is" on a date field, we need to match all times
    # within that calendar day in the user's local timezone.
    #
    # @param value [String, Hash] Date value (simple string or nested hash with date_mode_value)
    # @return [Hash, nil] Range condition {between: {min:, max:}} or nil if not a date-only value
    # @example
    #   convert_date_to_range("2026-06-15")  # In -0700 timezone
    #   #=> {between: {min: "2026-06-15T07:00:00Z", max: "2026-06-16T06:59:59Z"}}
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

      # Get timezone offset for the specific date (handles DST correctly)
      offset = local_timezone_offset(date_str)

      # Calculate start of day (midnight local) in UTC
      start_of_day_local = Time.parse("#{date_str}T00:00:00#{offset}")
      start_of_day_utc = start_of_day_local.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

      # Calculate end of day (23:59:59 local) in UTC
      end_of_day_local = Time.parse("#{date_str}T23:59:59#{offset}")
      end_of_day_utc = end_of_day_local.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

      { between: { min: start_of_day_utc, max: end_of_day_utc } }
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
