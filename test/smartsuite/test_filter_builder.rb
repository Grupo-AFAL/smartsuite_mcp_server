# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/smart_suite/filter_builder"
require_relative "../../lib/smart_suite/cache/query"
require_relative "../../lib/smart_suite/date_formatter"

class TestFilterBuilder < Minitest::Test
  def setup
    # Configure UTC timezone for predictable test results
    # Date-only values will be converted to UTC midnight (no offset)
    @original_timezone = SmartSuite::DateFormatter.timezone
    SmartSuite::DateFormatter.timezone = :utc

    # Create mock query object
    @query = Object.new
    @query.define_singleton_method(:where) do |conditions|
      @conditions ||= []
      @conditions << conditions
      self
    end
    @query.define_singleton_method(:conditions) { @conditions || [] }
  end

  def teardown
    # Restore original timezone
    SmartSuite::DateFormatter.timezone = @original_timezone
  end

  # Test equality operators
  def test_convert_comparison_is
    assert_equal "Active", SmartSuite::FilterBuilder.convert_comparison("is", "Active")
    assert_equal "Active", SmartSuite::FilterBuilder.convert_comparison("is_equal_to", "Active")
  end

  def test_convert_comparison_is_not
    assert_equal({ ne: "Inactive" }, SmartSuite::FilterBuilder.convert_comparison("is_not", "Inactive"))
    assert_equal({ ne: "Inactive" }, SmartSuite::FilterBuilder.convert_comparison("is_not_equal_to", "Inactive"))
  end

  # Test numeric operators
  def test_convert_comparison_greater_than
    assert_equal({ gt: 5 }, SmartSuite::FilterBuilder.convert_comparison("is_greater_than", 5))
  end

  def test_convert_comparison_less_than
    assert_equal({ lt: 10 }, SmartSuite::FilterBuilder.convert_comparison("is_less_than", 10))
  end

  def test_convert_comparison_gte
    assert_equal({ gte: 5 }, SmartSuite::FilterBuilder.convert_comparison("is_equal_or_greater_than", 5))
  end

  def test_convert_comparison_lte
    assert_equal({ lte: 10 }, SmartSuite::FilterBuilder.convert_comparison("is_equal_or_less_than", 10))
  end

  # Test text operators
  def test_convert_comparison_contains
    assert_equal({ contains: "test" }, SmartSuite::FilterBuilder.convert_comparison("contains", "test"))
  end

  def test_convert_comparison_not_contains
    assert_equal({ not_contains: "spam" }, SmartSuite::FilterBuilder.convert_comparison("not_contains", "spam"))
    assert_equal({ not_contains: "spam" },
                 SmartSuite::FilterBuilder.convert_comparison("does_not_contain", "spam"))
  end

  # Test null operators
  def test_convert_comparison_is_empty
    assert_equal({ is_empty: true }, SmartSuite::FilterBuilder.convert_comparison("is_empty", nil))
  end

  def test_convert_comparison_is_not_empty
    assert_equal({ is_not_empty: true }, SmartSuite::FilterBuilder.convert_comparison("is_not_empty", nil))
  end

  # Test array operators
  def test_convert_comparison_has_any_of
    assert_equal({ has_any_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("has_any_of", %w[a b]))
  end

  def test_convert_comparison_has_all_of
    assert_equal({ has_all_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("has_all_of", %w[a b]))
  end

  def test_convert_comparison_is_exactly
    assert_equal({ is_exactly: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("is_exactly", %w[a b]))
  end

  def test_convert_comparison_has_none_of
    assert_equal({ has_none_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("has_none_of", %w[a b]))
  end

  # Single select array operators (is_any_of, is_none_of)
  def test_convert_comparison_is_any_of_with_array
    assert_equal({ is_any_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("is_any_of", %w[a b]))
  end

  def test_convert_comparison_is_any_of_with_single_value
    # Single value should be wrapped in array
    assert_equal({ is_any_of: [ "a" ] }, SmartSuite::FilterBuilder.convert_comparison("is_any_of", "a"))
  end

  def test_convert_comparison_is_none_of_with_array
    assert_equal({ is_none_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison("is_none_of", %w[a b]))
  end

  def test_convert_comparison_is_none_of_with_single_value
    # Single value should be wrapped in array
    assert_equal({ is_none_of: [ "a" ] }, SmartSuite::FilterBuilder.convert_comparison("is_none_of", "a"))
  end

  # Test date operators
  # Note: Date-only strings are converted to UTC timestamps (start of day)
  # Date operators preserve their type for proper handling in postgres_layer
  def test_convert_comparison_is_before
    # With UTC timezone, 2025-01-01 becomes 2025-01-01T00:00:00Z
    assert_equal({ is_before: "2025-01-01T00:00:00Z" }, SmartSuite::FilterBuilder.convert_comparison("is_before", "2025-01-01"))
  end

  # Note: is_after does NOT exist in SmartSuite API - use is_on_or_after instead
  # The API only supports: is_before, is_on_or_before, is_on_or_after

  def test_convert_comparison_is_on_or_before
    assert_equal({ is_on_or_before: "2025-01-01T00:00:00Z" }, SmartSuite::FilterBuilder.convert_comparison("is_on_or_before", "2025-01-01"))
  end

  def test_convert_comparison_is_on_or_after
    assert_equal({ is_on_or_after: "2025-01-01T00:00:00Z" }, SmartSuite::FilterBuilder.convert_comparison("is_on_or_after", "2025-01-01"))
  end

  # Test default behavior for unknown operator
  def test_convert_comparison_unknown_operator
    assert_equal "value", SmartSuite::FilterBuilder.convert_comparison("unknown_operator", "value")
  end

  # Test apply_to_query with nil filter
  def test_apply_to_query_with_nil_filter
    result = SmartSuite::FilterBuilder.apply_to_query(@query, nil)
    assert_equal @query, result
    assert_empty @query.conditions
  end

  # Test apply_to_query with empty fields
  def test_apply_to_query_with_empty_fields
    filter = { "operator" => "and", "fields" => [] }
    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_empty @query.conditions
  end

  # Test apply_to_query with single field
  def test_apply_to_query_with_single_field
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
    assert_equal({ status: "Active" }, @query.conditions.first)
  end

  # Test apply_to_query with multiple fields
  def test_apply_to_query_with_multiple_fields
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" },
        { "field" => "priority", "comparison" => "is_greater_than", "value" => 3 }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 2, @query.conditions.size
    assert_equal({ status: "Active" }, @query.conditions[0])
    assert_equal({ priority: { gt: 3 } }, @query.conditions[1])
  end

  # Test apply_to_query with complex conditions
  def test_apply_to_query_with_complex_conditions
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "title", "comparison" => "contains", "value" => "Important" },
        { "field" => "tags", "comparison" => "has_any_of", "value" => %w[urgent critical] },
        { "field" => "due_date", "comparison" => "is_on_or_after", "value" => "2025-01-01" },
        { "field" => "assigned_to", "comparison" => "is_not_empty", "value" => nil }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 4, @query.conditions.size
    assert_equal({ title: { contains: "Important" } }, @query.conditions[0])
    assert_equal({ tags: { has_any_of: %w[urgent critical] } }, @query.conditions[1])
    # Date-only values are converted to UTC timestamp (date operators preserve type)
    assert_equal({ due_date: { is_on_or_after: "2025-01-01T00:00:00Z" } }, @query.conditions[2])
    assert_equal({ assigned_to: { is_not_empty: true } }, @query.conditions[3])
  end

  # Test that field names are converted to symbols
  def test_apply_to_query_converts_field_names_to_symbols
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" }
      ]
    }

    SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal :status, @query.conditions.first.keys.first
  end

  # Edge case: filter without operator key
  def test_apply_to_query_without_operator_key
    filter = {
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
  end

  # Edge case: numeric values
  def test_convert_comparison_with_numeric_values
    assert_equal({ gt: 100 }, SmartSuite::FilterBuilder.convert_comparison("is_greater_than", 100))
    assert_equal({ lt: 0.5 }, SmartSuite::FilterBuilder.convert_comparison("is_less_than", 0.5))
  end

  # Edge case: boolean values
  def test_convert_comparison_with_boolean_values
    assert_equal true, SmartSuite::FilterBuilder.convert_comparison("is", true)
    assert_equal false, SmartSuite::FilterBuilder.convert_comparison("is", false)
  end

  # Edge case: empty string values
  def test_convert_comparison_with_empty_string
    assert_equal "", SmartSuite::FilterBuilder.convert_comparison("is", "")
    assert_equal({ contains: "" }, SmartSuite::FilterBuilder.convert_comparison("contains", ""))
  end

  # Edge case: nested hash values (for date fields with mode)
  # Date-only values are now converted to a range for "is" operator
  def test_convert_comparison_with_nested_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-01-01" }
    result = SmartSuite::FilterBuilder.convert_comparison("is", date_value)
    # SmartSuite stores dates as UTC timestamps, so we match with a day range
    expected = { between: { min: "2025-01-01T00:00:00Z", max: "2025-01-01T23:59:59Z" } }
    assert_equal expected, result
  end

  # ============================================================================
  # REGRESSION TESTS: is_not_empty Filter Integration
  # ============================================================================
  # Bug: FilterBuilder returned {not_null: true} but Cache::Query expected
  # {is_not_null: true}, causing "can't prepare TrueClass" SQL binding error.
  # Fix: Changed FilterBuilder to return {is_not_null: true}

  # Test that is_not_empty produces the correct operator for Cache::Query
  def test_is_not_empty_returns_correct_operator
    result = SmartSuite::FilterBuilder.convert_comparison("is_not_empty", nil)

    # Returns {is_not_empty: true} which maps to "is_not_empty" comparison in postgres_layer
    assert result.is_a?(Hash), "Should return Hash"
    assert result.key?(:is_not_empty), "Should have :is_not_empty key"
    assert_equal true, result[:is_not_empty], "Value should be true"
  end

  # Test that is_empty returns correct operator
  def test_is_empty_returns_correct_operator
    result = SmartSuite::FilterBuilder.convert_comparison("is_empty", nil)
    # Returns {is_empty: true} which maps to "is_empty" comparison in postgres_layer
    assert result.is_a?(Hash), "Should return Hash"
    assert result.key?(:is_empty), "Should have :is_empty key"
    assert_equal true, result[:is_empty], "Value should be true"
  end

  # Test comprehensive filter operator integration to prevent similar bugs
  def test_all_operators_return_valid_query_conditions
    # Map of SmartSuite operators to expected Cache::Query operators
    test_cases = {
      # Equality
      "is" => "value",
      "is_not" => { ne: "value" },

      # Numeric comparisons
      "is_greater_than" => { gt: 5 },
      "is_less_than" => { lt: 5 },
      "is_equal_or_greater_than" => { gte: 5 },
      "is_equal_or_less_than" => { lte: 5 },

      # Text operators
      "contains" => { contains: "text" },
      "not_contains" => { not_contains: "text" },

      # Null operators - return explicit operator hashes for postgres_layer mapping
      "is_empty" => { is_empty: true },
      "is_not_empty" => { is_not_empty: true },

      # Array operators (multi-select fields)
      "has_any_of" => { has_any_of: [ "a" ] },
      "has_all_of" => { has_all_of: [ "a" ] },
      "is_exactly" => { is_exactly: [ "a" ] },
      "has_none_of" => { has_none_of: [ "a" ] },

      # Single select array operators
      "is_any_of" => { is_any_of: [ "a" ] },
      "is_none_of" => { is_none_of: [ "a" ] },

      # Date operators (preserve type for proper handling in postgres_layer)
      # Note: is_after does NOT exist in SmartSuite API
      "is_before" => { is_before: "2025-01-01T00:00:00Z" },
      "is_on_or_before" => { is_on_or_before: "2025-01-01T00:00:00Z" },
      "is_on_or_after" => { is_on_or_after: "2025-01-01T00:00:00Z" },

      # Due Date special operators (duedatefield only)
      "is_overdue" => { is_overdue: true },
      "is_not_overdue" => { is_not_overdue: true },

      # File field operators (filefield only)
      "file_name_contains" => { file_name_contains: "report" },
      "file_type_is" => { file_type_is: "pdf" }
    }

    test_cases.each do |operator, expected|
      value = case operator
      when "is_greater_than", "is_less_than", "is_equal_or_greater_than", "is_equal_or_less_than"
                5
      when "has_any_of", "has_all_of", "is_exactly", "has_none_of", "is_any_of", "is_none_of"
                [ "a" ]
      when "is_before", "is_on_or_before", "is_on_or_after"
                "2025-01-01"
      when "is_empty", "is_not_empty", "is_overdue", "is_not_overdue"
                nil
      when "contains", "not_contains"
                "text"
      when "file_name_contains"
                "report"
      when "file_type_is"
                "pdf"
      else
                "value"
      end

      result = SmartSuite::FilterBuilder.convert_comparison(operator, value)
      if expected.nil?
        assert_nil result, "Operator '#{operator}' should return nil"
      else
        assert_equal expected, result, "Operator '#{operator}' failed"
      end
    end
  end

  # Test that no operators produce invalid conditions that would cause SQL errors
  def test_no_operators_produce_unprepared_types
    # The original bug: FilterBuilder returned {not_null: true} which tried to bind
    # `true` directly as SQL parameter. Now it returns {is_not_null: true} which
    # Cache::Query correctly interprets as "IS NOT NULL" SQL (no boolean binding).

    all_operators = %w[
      is is_not is_greater_than is_less_than is_equal_or_greater_than is_equal_or_less_than
      contains not_contains is_empty is_not_empty has_any_of has_all_of is_exactly has_none_of
      is_any_of is_none_of is_before is_on_or_before is_on_or_after
      is_overdue is_not_overdue file_name_contains file_type_is
    ]

    all_operators.each do |operator|
      value = operator.include?("empty") ? nil : "test"
      result = SmartSuite::FilterBuilder.convert_comparison(operator, value)

      # Result should be either a simple value, nil, or a Hash with operator keys
      next unless result.is_a?(Hash)

      # Verify the hash has valid Cache::Query operator keys
      # These are the operator symbols Cache::Query.build_complex_condition recognizes
      valid_operators = %i[eq ne gt gte lt lte contains not_contains starts_with ends_with
                           in not_in between is_null is_not_null is_empty is_not_empty
                           has_any_of has_all_of is_exactly has_none_of is_any_of is_none_of
                           is_before is_on_or_before is_on_or_after
                           is_overdue is_not_overdue file_name_contains file_type_is]

      result.each_key do |key|
        assert valid_operators.include?(key),
               "Operator '#{operator}' produced unknown key :#{key}"
      end
    end
  end

  # ============================================================================
  # REGRESSION TESTS: Date Filter with Nested Hash Values
  # ============================================================================
  # Bug: When date filters came with nested hash format from SmartSuite API:
  # {"field":"due_date", "comparison":"is_after", "value":{"date_mode":"exact_date","date_mode_value":"2025-01-01"}}
  # FilterBuilder passed the entire hash to Cache::Query which tried to bind it
  # as an SQL parameter, causing "no such bind parameter" SQLite error.
  # Fix: Added extract_date_value helper to extract date_mode_value from nested hash

  # Test extract_date_value helper method
  # Note: Date-only strings are converted to UTC timestamps
  def test_extract_date_value_with_simple_string
    result = SmartSuite::FilterBuilder.extract_date_value("2025-01-01")
    # With UTC timezone, date-only becomes midnight UTC
    assert_equal "2025-01-01T00:00:00Z", result
  end

  def test_extract_date_value_with_nested_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-11-18" }
    result = SmartSuite::FilterBuilder.extract_date_value(date_value)
    # With UTC timezone, date-only becomes midnight UTC
    assert_equal "2025-11-18T00:00:00Z", result
  end

  def test_extract_date_value_with_nil
    result = SmartSuite::FilterBuilder.extract_date_value(nil)
    assert_nil result
  end

  # Test convert_comparison with nested date hash for all date operators
  # Note: Date-only strings are converted to UTC timestamps
  # Note: is_after does NOT exist in SmartSuite API - removed test
  # Use is_on_or_after instead

  def test_is_before_with_nested_date_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-11-18" }
    result = SmartSuite::FilterBuilder.convert_comparison("is_before", date_value)
    assert_equal({ is_before: "2025-11-18T00:00:00Z" }, result)
  end

  def test_is_on_or_after_with_nested_date_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-11-18" }
    result = SmartSuite::FilterBuilder.convert_comparison("is_on_or_after", date_value)
    assert_equal({ is_on_or_after: "2025-11-18T00:00:00Z" }, result)
  end

  def test_is_on_or_before_with_nested_date_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-11-18" }
    result = SmartSuite::FilterBuilder.convert_comparison("is_on_or_before", date_value)
    assert_equal({ is_on_or_before: "2025-11-18T00:00:00Z" }, result)
  end

  # Test that simple date strings still work (converted to UTC)
  # Note: is_after does NOT exist in SmartSuite API - removed test

  def test_is_before_with_simple_date_string
    result = SmartSuite::FilterBuilder.convert_comparison("is_before", "2025-11-18")
    assert_equal({ is_before: "2025-11-18T00:00:00Z" }, result)
  end

  # Integration test: apply_to_query with nested date filter
  # Note: Changed from is_after to is_on_or_after (is_after doesn't exist in SmartSuite API)
  def test_apply_to_query_with_nested_date_filter
    filter = {
      "operator" => "and",
      "fields" => [
        {
          "field" => "due_date",
          "comparison" => "is_on_or_after",
          "value" => { "date_mode" => "exact_date", "date_mode_value" => "2025-11-18" }
        }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
    # Should extract date string from nested hash, convert to UTC, and preserve operator type
    assert_equal({ due_date: { is_on_or_after: "2025-11-18T00:00:00Z" } }, @query.conditions.first)
  end

  # Integration test: multiple date filters with mixed formats
  def test_apply_to_query_with_mixed_date_formats
    filter = {
      "operator" => "and",
      "fields" => [
        {
          "field" => "start_date",
          "comparison" => "is_on_or_after",
          "value" => { "date_mode" => "exact_date", "date_mode_value" => "2025-01-01" }
        },
        {
          "field" => "end_date",
          "comparison" => "is_on_or_before",
          "value" => "2025-12-31" # Simple string format
        }
      ]
    }

    SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal 2, @query.conditions.size
    # Both dates converted to UTC timestamps, operator types preserved
    assert_equal({ start_date: { is_on_or_after: "2025-01-01T00:00:00Z" } }, @query.conditions[0])
    assert_equal({ end_date: { is_on_or_before: "2025-12-31T00:00:00Z" } }, @query.conditions[1])
  end

  # Test that datetime strings with time component are not modified
  def test_extract_date_value_with_datetime_string
    # Datetime with time component should pass through unchanged
    result = SmartSuite::FilterBuilder.extract_date_value("2025-06-15T14:30:00Z")
    assert_equal "2025-06-15T14:30:00Z", result
  end

  # Test timezone offset conversion
  def test_date_filter_with_local_timezone
    # Temporarily set a non-UTC timezone
    SmartSuite::DateFormatter.timezone = "-0700"

    result = SmartSuite::FilterBuilder.extract_date_value("2026-06-15")
    # Midnight in -0700 is 07:00 UTC
    assert_equal "2026-06-15T07:00:00Z", result

    # Restore UTC for other tests
    SmartSuite::DateFormatter.timezone = :utc
  end

  # ============================================================================
  # NEW OPERATORS: Due Date Special (is_overdue, is_not_overdue)
  # ============================================================================

  def test_convert_comparison_is_overdue
    result = SmartSuite::FilterBuilder.convert_comparison("is_overdue", nil)
    assert_equal({ is_overdue: true }, result)
  end

  def test_convert_comparison_is_not_overdue
    result = SmartSuite::FilterBuilder.convert_comparison("is_not_overdue", nil)
    assert_equal({ is_not_overdue: true }, result)
  end

  # ============================================================================
  # NEW OPERATORS: File Field (file_name_contains, file_type_is)
  # ============================================================================

  def test_convert_comparison_file_name_contains
    result = SmartSuite::FilterBuilder.convert_comparison("file_name_contains", "report")
    assert_equal({ file_name_contains: "report" }, result)
  end

  def test_convert_comparison_file_type_is
    result = SmartSuite::FilterBuilder.convert_comparison("file_type_is", "pdf")
    assert_equal({ file_type_is: "pdf" }, result)
  end

  # Test that file_type_is works with all valid file types
  def test_file_type_is_valid_types
    valid_types = %w[archive image music pdf powerpoint spreadsheet video word other]

    valid_types.each do |file_type|
      result = SmartSuite::FilterBuilder.convert_comparison("file_type_is", file_type)
      assert_equal({ file_type_is: file_type }, result, "Failed for file type: #{file_type}")
    end
  end

  # ============================================================================
  # NEW: is_not for Date Fields (Issue #1)
  # ============================================================================

  def test_convert_comparison_is_not_with_date_string
    # Date-only string should be converted to not_between range (using UTC timestamps)
    result = SmartSuite::FilterBuilder.convert_comparison("is_not", "2025-01-15")
    expected = { not_between: { min: "2025-01-15T00:00:00Z", max: "2025-01-15T23:59:59Z" } }
    assert_equal expected, result
  end

  def test_convert_comparison_is_not_with_nested_date_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-06-20" }
    result = SmartSuite::FilterBuilder.convert_comparison("is_not", date_value)
    expected = { not_between: { min: "2025-06-20T00:00:00Z", max: "2025-06-20T23:59:59Z" } }
    assert_equal expected, result
  end

  def test_convert_comparison_is_not_with_non_date_value
    # Non-date values should return simple ne operator
    result = SmartSuite::FilterBuilder.convert_comparison("is_not", "Active")
    assert_equal({ ne: "Active" }, result)
  end

  def test_convert_comparison_is_not_with_numeric_value
    # Numeric values should return simple ne operator
    result = SmartSuite::FilterBuilder.convert_comparison("is_not", 42)
    assert_equal({ ne: 42 }, result)
  end

  def test_convert_date_to_not_range_simple_date
    result = SmartSuite::FilterBuilder.convert_date_to_not_range("2025-03-10")
    # Uses UTC timestamps to match how SmartSuite stores dates
    expected = { not_between: { min: "2025-03-10T00:00:00Z", max: "2025-03-10T23:59:59Z" } }
    assert_equal expected, result
  end

  def test_convert_date_to_not_range_nested_hash
    date_value = { "date_mode" => "exact_date", "date_mode_value" => "2025-12-25" }
    result = SmartSuite::FilterBuilder.convert_date_to_not_range(date_value)
    expected = { not_between: { min: "2025-12-25T00:00:00Z", max: "2025-12-25T23:59:59Z" } }
    assert_equal expected, result
  end

  def test_convert_date_to_not_range_returns_nil_for_non_date
    assert_nil SmartSuite::FilterBuilder.convert_date_to_not_range("Active")
    assert_nil SmartSuite::FilterBuilder.convert_date_to_not_range(42)
    assert_nil SmartSuite::FilterBuilder.convert_date_to_not_range(nil)
    assert_nil SmartSuite::FilterBuilder.convert_date_to_not_range({})
  end

  def test_convert_date_to_not_range_with_timezone
    # Date conversion uses UTC timestamps regardless of local timezone
    SmartSuite::DateFormatter.timezone = "-0700"

    result = SmartSuite::FilterBuilder.convert_date_to_not_range("2026-06-15")
    # UTC timestamps are used to match SmartSuite storage format
    expected = { not_between: { min: "2026-06-15T00:00:00Z", max: "2026-06-15T23:59:59Z" } }
    assert_equal expected, result

    # Restore UTC
    SmartSuite::DateFormatter.timezone = :utc
  end

  # Integration test: apply_to_query with due date overdue filter
  def test_apply_to_query_with_is_overdue_filter
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "due_date", "comparison" => "is_overdue", "value" => nil }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
    assert_equal({ due_date: { is_overdue: true } }, @query.conditions.first)
  end

  # Integration test: apply_to_query with file filter
  def test_apply_to_query_with_file_filter
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "attachments", "comparison" => "file_type_is", "value" => "pdf" },
        { "field" => "attachments", "comparison" => "file_name_contains", "value" => "invoice" }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 2, @query.conditions.size
    assert_equal({ attachments: { file_type_is: "pdf" } }, @query.conditions[0])
    assert_equal({ attachments: { file_name_contains: "invoice" } }, @query.conditions[1])
  end

  # ============================================================================
  # NEW: Nested Filter Support (Issue #3)
  # ============================================================================

  # Test detection of nested filters
  def test_nested_filter_detection_with_flat_filter
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" },
        { "field" => "priority", "comparison" => "is_greater_than", "value" => 3 }
      ]
    }

    # Flat filter should use normal where() chain, not where_raw()
    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 2, @query.conditions.size
    assert_equal({ status: "Active" }, @query.conditions[0])
    assert_equal({ priority: { gt: 3 } }, @query.conditions[1])
  end

  def test_nested_filter_structure_detected
    # Create a mock query that tracks where_raw calls
    mock_query = Object.new
    mock_query.define_singleton_method(:where_raw_calls) { @where_raw_calls ||= [] }
    mock_query.define_singleton_method(:where_raw) do |clause, params|
      @where_raw_calls ||= []
      @where_raw_calls << { clause: clause, params: params }
      self
    end
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      # Return mock SQL for testing
      [ "#{field_slug} = ?", [ condition.is_a?(Hash) ? condition.values.first : condition ] ]
    end

    filter = {
      "operator" => "or",
      "fields" => [
        {
          "operator" => "and",
          "fields" => [
            { "field" => "status", "comparison" => "is", "value" => "active" },
            { "field" => "priority", "comparison" => "is", "value" => "high" }
          ]
        },
        { "field" => "overdue", "comparison" => "is", "value" => true }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(mock_query, filter)
    assert_equal mock_query, result

    # Should have called where_raw (nested filter detected)
    assert_equal 1, mock_query.where_raw_calls.size

    # The clause should use OR operator
    clause = mock_query.where_raw_calls.first[:clause]
    assert_includes clause, " OR "
  end

  def test_build_filter_group_sql_flat_and
    mock_query = Object.new
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      [ "#{field_slug}_col = ?", [ condition.is_a?(Hash) ? condition.values.first : condition ] ]
    end

    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" },
        { "field" => "priority", "comparison" => "is", "value" => "High" }
      ]
    }

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    assert_equal "status_col = ? AND priority_col = ?", clause
    assert_equal %w[Active High], params
  end

  def test_build_filter_group_sql_flat_or
    mock_query = Object.new
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      [ "#{field_slug}_col = ?", [ condition.is_a?(Hash) ? condition.values.first : condition ] ]
    end

    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "Active" },
        { "field" => "status", "comparison" => "is", "value" => "Pending" }
      ]
    }

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    assert_equal "status_col = ? OR status_col = ?", clause
    assert_equal %w[Active Pending], params
  end

  def test_build_filter_group_sql_nested_and_or
    mock_query = Object.new
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      [ "#{field_slug}_col = ?", [ condition.is_a?(Hash) ? condition.values.first : condition ] ]
    end

    # "(status=Active AND priority=High) OR (overdue=true)"
    filter = {
      "operator" => "or",
      "fields" => [
        {
          "operator" => "and",
          "fields" => [
            { "field" => "status", "comparison" => "is", "value" => "Active" },
            { "field" => "priority", "comparison" => "is", "value" => "High" }
          ]
        },
        { "field" => "overdue", "comparison" => "is", "value" => true }
      ]
    }

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    # Nested AND group should be wrapped in parentheses
    assert_equal "(status_col = ? AND priority_col = ?) OR overdue_col = ?", clause
    assert_equal [ "Active", "High", true ], params
  end

  def test_build_filter_group_sql_deeply_nested
    mock_query = Object.new
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      [ "#{field_slug} = ?", [ condition.is_a?(Hash) ? condition.values.first : condition ] ]
    end

    # ((A AND B) OR (C AND D)) AND E
    filter = {
      "operator" => "and",
      "fields" => [
        {
          "operator" => "or",
          "fields" => [
            {
              "operator" => "and",
              "fields" => [
                { "field" => "a", "comparison" => "is", "value" => "A" },
                { "field" => "b", "comparison" => "is", "value" => "B" }
              ]
            },
            {
              "operator" => "and",
              "fields" => [
                { "field" => "c", "comparison" => "is", "value" => "C" },
                { "field" => "d", "comparison" => "is", "value" => "D" }
              ]
            }
          ]
        },
        { "field" => "e", "comparison" => "is", "value" => "E" }
      ]
    }

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    # Verify structure: ((A AND B) OR (C AND D)) AND E
    assert_includes clause, "((a = ? AND b = ?) OR (c = ? AND d = ?))"
    assert_includes clause, " AND e = ?"
    assert_equal %w[A B C D E], params
  end

  def test_build_filter_group_sql_empty_fields
    mock_query = Object.new

    filter = { "operator" => "and", "fields" => [] }
    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    assert_nil clause
    assert_equal [], params
  end

  def test_build_filter_group_sql_nil_filter
    mock_query = Object.new

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, nil)

    assert_nil clause
    assert_equal [], params
  end

  def test_build_filter_group_sql_default_operator_is_and
    mock_query = Object.new
    mock_query.define_singleton_method(:build_condition_sql) do |field_slug, condition|
      [ "#{field_slug} = ?", [ condition ] ]
    end

    # No operator specified - should default to AND
    filter = {
      "fields" => [
        { "field" => "a", "comparison" => "is", "value" => "1" },
        { "field" => "b", "comparison" => "is", "value" => "2" }
      ]
    }

    clause, params = SmartSuite::FilterBuilder.build_filter_group_sql(mock_query, filter)

    assert_equal "a = ? AND b = ?", clause
    assert_equal %w[1 2], params
  end

  # ============================================================================
  # Filter Validation Tests
  # ============================================================================

  def test_validate_filter_operator_returns_true_for_valid_combination
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "textfield" }

    result = SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "name", "contains")
    assert result, "Expected 'contains' to be valid for textfield"
  end

  def test_validate_filter_operator_returns_false_for_invalid_combination
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "numberfield" }

    result = SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "amount", "contains")
    refute result, "Expected 'contains' to be invalid for numberfield"
  end

  def test_validate_filter_operator_returns_true_when_query_has_no_get_field_type
    mock_query = Object.new
    # No get_field_type method

    result = SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "field", "contains")
    assert result, "Expected true when query doesn't support get_field_type"
  end

  def test_validate_filter_operator_returns_true_when_field_type_is_nil
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| nil }

    result = SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "unknown_field", "contains")
    assert result, "Expected true when field type is nil (unknown field)"
  end

  def test_validate_filter_operator_with_numeric_operators_on_textfield
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "textfield" }

    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "name", "is_greater_than")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "name", "is_less_than")
  end

  def test_validate_filter_operator_with_text_operators_on_numberfield
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "numberfield" }

    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "amount", "contains")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "amount", "not_contains")
  end

  def test_validate_filter_operator_with_date_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "datefield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is_before")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is_on_or_after")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "contains")
  end

  def test_validate_filter_operator_with_duedate_special_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "duedatefield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is_overdue")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is_not_overdue")
    # Regular date operators should also work
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "due", "is_before")
  end

  def test_validate_filter_operator_with_single_select_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "statusfield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "status", "is")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "status", "is_any_of")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "status", "has_any_of")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "status", "contains")
  end

  def test_validate_filter_operator_with_multiple_select_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "multipleselectfield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "tags", "has_any_of")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "tags", "has_all_of")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "tags", "is_exactly")
    # 'is' is NOT valid for multiple select
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "tags", "is")
  end

  def test_validate_filter_operator_with_linked_record_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "linkedrecordfield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "project", "has_any_of")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "project", "contains")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "project", "is")
  end

  def test_validate_filter_operator_with_user_field_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "assignedtofield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "assigned", "has_any_of")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "assigned", "is")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "assigned", "contains")
  end

  def test_validate_filter_operator_with_file_field_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "filefield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "attachments", "file_name_contains")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "attachments", "file_type_is")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "attachments", "is_empty")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "attachments", "contains")
  end

  def test_validate_filter_operator_with_yesno_field_operators
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "yesnofield" }

    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "active", "is")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "active", "contains")
    refute SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "active", "is_greater_than")
  end

  def test_validate_filter_operator_with_formula_field_skips_validation
    mock_query = Object.new
    mock_query.define_singleton_method(:get_field_type) { |_slug| "formulafield" }

    # Formula fields can't be validated without knowing return type
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "calculated", "contains")
    assert SmartSuite::FilterBuilder.validate_filter_operator(mock_query, "calculated", "is_greater_than")
  end
end
