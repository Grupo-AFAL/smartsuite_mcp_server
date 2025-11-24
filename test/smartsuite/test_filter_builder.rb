# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/smartsuite/filter_builder'
require_relative '../../lib/smartsuite/cache/query'
require_relative '../../lib/smartsuite/date_formatter'

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
    assert_equal 'Active', SmartSuite::FilterBuilder.convert_comparison('is', 'Active')
    assert_equal 'Active', SmartSuite::FilterBuilder.convert_comparison('is_equal_to', 'Active')
  end

  def test_convert_comparison_is_not
    assert_equal({ ne: 'Inactive' }, SmartSuite::FilterBuilder.convert_comparison('is_not', 'Inactive'))
    assert_equal({ ne: 'Inactive' }, SmartSuite::FilterBuilder.convert_comparison('is_not_equal_to', 'Inactive'))
  end

  # Test numeric operators
  def test_convert_comparison_greater_than
    assert_equal({ gt: 5 }, SmartSuite::FilterBuilder.convert_comparison('is_greater_than', 5))
  end

  def test_convert_comparison_less_than
    assert_equal({ lt: 10 }, SmartSuite::FilterBuilder.convert_comparison('is_less_than', 10))
  end

  def test_convert_comparison_gte
    assert_equal({ gte: 5 }, SmartSuite::FilterBuilder.convert_comparison('is_equal_or_greater_than', 5))
  end

  def test_convert_comparison_lte
    assert_equal({ lte: 10 }, SmartSuite::FilterBuilder.convert_comparison('is_equal_or_less_than', 10))
  end

  # Test text operators
  def test_convert_comparison_contains
    assert_equal({ contains: 'test' }, SmartSuite::FilterBuilder.convert_comparison('contains', 'test'))
  end

  def test_convert_comparison_not_contains
    assert_equal({ not_contains: 'spam' }, SmartSuite::FilterBuilder.convert_comparison('not_contains', 'spam'))
    assert_equal({ not_contains: 'spam' },
                 SmartSuite::FilterBuilder.convert_comparison('does_not_contain', 'spam'))
  end

  # Test null operators
  def test_convert_comparison_is_empty
    assert_nil SmartSuite::FilterBuilder.convert_comparison('is_empty', nil)
  end

  def test_convert_comparison_is_not_empty
    assert_equal({ is_not_null: true }, SmartSuite::FilterBuilder.convert_comparison('is_not_empty', nil))
  end

  # Test array operators
  def test_convert_comparison_has_any_of
    assert_equal({ has_any_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison('has_any_of', %w[a b]))
  end

  def test_convert_comparison_has_all_of
    assert_equal({ has_all_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison('has_all_of', %w[a b]))
  end

  def test_convert_comparison_is_exactly
    assert_equal({ is_exactly: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison('is_exactly', %w[a b]))
  end

  def test_convert_comparison_has_none_of
    assert_equal({ has_none_of: %w[a b] }, SmartSuite::FilterBuilder.convert_comparison('has_none_of', %w[a b]))
  end

  # Test date operators
  # Note: Date-only strings are converted to UTC timestamps (start of day)
  def test_convert_comparison_is_before
    # With UTC timezone, 2025-01-01 becomes 2025-01-01T00:00:00Z
    assert_equal({ lt: '2025-01-01T00:00:00Z' }, SmartSuite::FilterBuilder.convert_comparison('is_before', '2025-01-01'))
  end

  def test_convert_comparison_is_after
    assert_equal({ gt: '2025-01-01T00:00:00Z' }, SmartSuite::FilterBuilder.convert_comparison('is_after', '2025-01-01'))
  end

  def test_convert_comparison_is_on_or_before
    assert_equal({ lte: '2025-01-01T00:00:00Z' }, SmartSuite::FilterBuilder.convert_comparison('is_on_or_before', '2025-01-01'))
  end

  def test_convert_comparison_is_on_or_after
    assert_equal({ gte: '2025-01-01T00:00:00Z' }, SmartSuite::FilterBuilder.convert_comparison('is_on_or_after', '2025-01-01'))
  end

  # Test default behavior for unknown operator
  def test_convert_comparison_unknown_operator
    assert_equal 'value', SmartSuite::FilterBuilder.convert_comparison('unknown_operator', 'value')
  end

  # Test apply_to_query with nil filter
  def test_apply_to_query_with_nil_filter
    result = SmartSuite::FilterBuilder.apply_to_query(@query, nil)
    assert_equal @query, result
    assert_empty @query.conditions
  end

  # Test apply_to_query with empty fields
  def test_apply_to_query_with_empty_fields
    filter = { 'operator' => 'and', 'fields' => [] }
    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_empty @query.conditions
  end

  # Test apply_to_query with single field
  def test_apply_to_query_with_single_field
    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
    assert_equal({ status: 'Active' }, @query.conditions.first)
  end

  # Test apply_to_query with multiple fields
  def test_apply_to_query_with_multiple_fields
    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' },
        { 'field' => 'priority', 'comparison' => 'is_greater_than', 'value' => 3 }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 2, @query.conditions.size
    assert_equal({ status: 'Active' }, @query.conditions[0])
    assert_equal({ priority: { gt: 3 } }, @query.conditions[1])
  end

  # Test apply_to_query with complex conditions
  def test_apply_to_query_with_complex_conditions
    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'title', 'comparison' => 'contains', 'value' => 'Important' },
        { 'field' => 'tags', 'comparison' => 'has_any_of', 'value' => %w[urgent critical] },
        { 'field' => 'due_date', 'comparison' => 'is_on_or_after', 'value' => '2025-01-01' },
        { 'field' => 'assigned_to', 'comparison' => 'is_not_empty', 'value' => nil }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 4, @query.conditions.size
    assert_equal({ title: { contains: 'Important' } }, @query.conditions[0])
    assert_equal({ tags: { has_any_of: %w[urgent critical] } }, @query.conditions[1])
    # Date-only values are converted to UTC timestamp
    assert_equal({ due_date: { gte: '2025-01-01T00:00:00Z' } }, @query.conditions[2])
    assert_equal({ assigned_to: { is_not_null: true } }, @query.conditions[3])
  end

  # Test that field names are converted to symbols
  def test_apply_to_query_converts_field_names_to_symbols
    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' }
      ]
    }

    SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal :status, @query.conditions.first.keys.first
  end

  # Edge case: filter without operator key
  def test_apply_to_query_without_operator_key
    filter = {
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
  end

  # Edge case: numeric values
  def test_convert_comparison_with_numeric_values
    assert_equal({ gt: 100 }, SmartSuite::FilterBuilder.convert_comparison('is_greater_than', 100))
    assert_equal({ lt: 0.5 }, SmartSuite::FilterBuilder.convert_comparison('is_less_than', 0.5))
  end

  # Edge case: boolean values
  def test_convert_comparison_with_boolean_values
    assert_equal true, SmartSuite::FilterBuilder.convert_comparison('is', true)
    assert_equal false, SmartSuite::FilterBuilder.convert_comparison('is', false)
  end

  # Edge case: empty string values
  def test_convert_comparison_with_empty_string
    assert_equal '', SmartSuite::FilterBuilder.convert_comparison('is', '')
    assert_equal({ contains: '' }, SmartSuite::FilterBuilder.convert_comparison('contains', ''))
  end

  # Edge case: nested hash values (for date fields with mode)
  # Date-only values are now converted to a range for "is" operator
  def test_convert_comparison_with_nested_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-01-01' }
    result = SmartSuite::FilterBuilder.convert_comparison('is', date_value)
    # With UTC timezone, date-only becomes a range covering the whole day
    expected = { between: { min: '2025-01-01T00:00:00Z', max: '2025-01-01T23:59:59Z' } }
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
    result = SmartSuite::FilterBuilder.convert_comparison('is_not_empty', nil)

    # CRITICAL: Must be :is_not_null, not :not_null
    assert result.is_a?(Hash), 'Should return Hash'
    assert result.key?(:is_not_null), 'Should have :is_not_null key'
    refute result.key?(:not_null), 'Should NOT have :not_null key (causes SQL binding error)'
    assert_equal true, result[:is_not_null], 'Value should be true'
  end

  # Test that is_empty still works correctly
  def test_is_empty_returns_nil
    result = SmartSuite::FilterBuilder.convert_comparison('is_empty', nil)
    assert_nil result, 'is_empty should return nil'
  end

  # Test comprehensive filter operator integration to prevent similar bugs
  def test_all_operators_return_valid_query_conditions
    # Map of SmartSuite operators to expected Cache::Query operators
    test_cases = {
      # Equality
      'is' => 'value',
      'is_not' => { ne: 'value' },

      # Numeric comparisons
      'is_greater_than' => { gt: 5 },
      'is_less_than' => { lt: 5 },
      'is_equal_or_greater_than' => { gte: 5 },
      'is_equal_or_less_than' => { lte: 5 },

      # Text operators
      'contains' => { contains: 'text' },
      'not_contains' => { not_contains: 'text' },

      # Null operators (CRITICAL for regression)
      'is_empty' => nil,
      'is_not_empty' => { is_not_null: true },

      # Array operators
      'has_any_of' => { has_any_of: ['a'] },
      'has_all_of' => { has_all_of: ['a'] },
      'is_exactly' => { is_exactly: ['a'] },
      'has_none_of' => { has_none_of: ['a'] },

      # Date operators (date-only values are converted to UTC timestamps)
      'is_before' => { lt: '2025-01-01T00:00:00Z' },
      'is_after' => { gt: '2025-01-01T00:00:00Z' },
      'is_on_or_before' => { lte: '2025-01-01T00:00:00Z' },
      'is_on_or_after' => { gte: '2025-01-01T00:00:00Z' }
    }

    test_cases.each do |operator, expected|
      value = case operator
              when 'is_greater_than', 'is_less_than', 'is_equal_or_greater_than', 'is_equal_or_less_than'
                5
              when 'has_any_of', 'has_all_of', 'is_exactly', 'has_none_of'
                ['a']
              when 'is_before', 'is_after', 'is_on_or_before', 'is_on_or_after'
                '2025-01-01'
              when 'is_empty', 'is_not_empty'
                nil
              when 'contains', 'not_contains'
                'text'
              else
                'value'
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
      is_before is_after is_on_or_before is_on_or_after
    ]

    all_operators.each do |operator|
      value = operator.include?('empty') ? nil : 'test'
      result = SmartSuite::FilterBuilder.convert_comparison(operator, value)

      # Result should be either a simple value, nil, or a Hash with operator keys
      next unless result.is_a?(Hash)

      # Verify the hash has valid Cache::Query operator keys
      # These are the operator symbols Cache::Query.build_complex_condition recognizes
      valid_operators = %i[eq ne gt gte lt lte contains not_contains starts_with ends_with
                           in not_in between is_null is_not_null is_empty is_not_empty
                           has_any_of has_all_of is_exactly has_none_of]

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
    result = SmartSuite::FilterBuilder.extract_date_value('2025-01-01')
    # With UTC timezone, date-only becomes midnight UTC
    assert_equal '2025-01-01T00:00:00Z', result
  end

  def test_extract_date_value_with_nested_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
    result = SmartSuite::FilterBuilder.extract_date_value(date_value)
    # With UTC timezone, date-only becomes midnight UTC
    assert_equal '2025-11-18T00:00:00Z', result
  end

  def test_extract_date_value_with_nil
    result = SmartSuite::FilterBuilder.extract_date_value(nil)
    assert_nil result
  end

  # Test convert_comparison with nested date hash for all date operators
  # Note: Date-only strings are converted to UTC timestamps
  def test_is_after_with_nested_date_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
    result = SmartSuite::FilterBuilder.convert_comparison('is_after', date_value)
    # CRITICAL: Should extract the date string and convert to UTC
    assert_equal({ gt: '2025-11-18T00:00:00Z' }, result)
  end

  def test_is_before_with_nested_date_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
    result = SmartSuite::FilterBuilder.convert_comparison('is_before', date_value)
    assert_equal({ lt: '2025-11-18T00:00:00Z' }, result)
  end

  def test_is_on_or_after_with_nested_date_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
    result = SmartSuite::FilterBuilder.convert_comparison('is_on_or_after', date_value)
    assert_equal({ gte: '2025-11-18T00:00:00Z' }, result)
  end

  def test_is_on_or_before_with_nested_date_hash
    date_value = { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
    result = SmartSuite::FilterBuilder.convert_comparison('is_on_or_before', date_value)
    assert_equal({ lte: '2025-11-18T00:00:00Z' }, result)
  end

  # Test that simple date strings still work (converted to UTC)
  def test_is_after_with_simple_date_string
    result = SmartSuite::FilterBuilder.convert_comparison('is_after', '2025-11-18')
    assert_equal({ gt: '2025-11-18T00:00:00Z' }, result)
  end

  def test_is_before_with_simple_date_string
    result = SmartSuite::FilterBuilder.convert_comparison('is_before', '2025-11-18')
    assert_equal({ lt: '2025-11-18T00:00:00Z' }, result)
  end

  # Integration test: apply_to_query with nested date filter
  def test_apply_to_query_with_nested_date_filter
    filter = {
      'operator' => 'and',
      'fields' => [
        {
          'field' => 'due_date',
          'comparison' => 'is_after',
          'value' => { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-11-18' }
        }
      ]
    }

    result = SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal @query, result
    assert_equal 1, @query.conditions.size
    # Should extract date string from nested hash and convert to UTC
    assert_equal({ due_date: { gt: '2025-11-18T00:00:00Z' } }, @query.conditions.first)
  end

  # Integration test: multiple date filters with mixed formats
  def test_apply_to_query_with_mixed_date_formats
    filter = {
      'operator' => 'and',
      'fields' => [
        {
          'field' => 'start_date',
          'comparison' => 'is_on_or_after',
          'value' => { 'date_mode' => 'exact_date', 'date_mode_value' => '2025-01-01' }
        },
        {
          'field' => 'end_date',
          'comparison' => 'is_on_or_before',
          'value' => '2025-12-31' # Simple string format
        }
      ]
    }

    SmartSuite::FilterBuilder.apply_to_query(@query, filter)
    assert_equal 2, @query.conditions.size
    # Both dates converted to UTC timestamps
    assert_equal({ start_date: { gte: '2025-01-01T00:00:00Z' } }, @query.conditions[0])
    assert_equal({ end_date: { lte: '2025-12-31T00:00:00Z' } }, @query.conditions[1])
  end

  # Test that datetime strings with time component are not modified
  def test_extract_date_value_with_datetime_string
    # Datetime with time component should pass through unchanged
    result = SmartSuite::FilterBuilder.extract_date_value('2025-06-15T14:30:00Z')
    assert_equal '2025-06-15T14:30:00Z', result
  end

  # Test timezone offset conversion
  def test_date_filter_with_local_timezone
    # Temporarily set a non-UTC timezone
    SmartSuite::DateFormatter.timezone = '-0700'

    result = SmartSuite::FilterBuilder.extract_date_value('2026-06-15')
    # Midnight in -0700 is 07:00 UTC
    assert_equal '2026-06-15T07:00:00Z', result

    # Restore UTC for other tests
    SmartSuite::DateFormatter.timezone = :utc
  end
end
