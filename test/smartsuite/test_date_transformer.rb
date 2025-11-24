# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/smartsuite/date_transformer'

class TestDateTransformer < Minitest::Test
  # ===================
  # Date Detection Tests
  # ===================

  def test_date_only_pattern
    assert SmartSuite::DateTransformer.date_only?('2025-06-20')
    assert SmartSuite::DateTransformer.date_only?('2025/06/20')
    refute SmartSuite::DateTransformer.date_only?('2025-06-20T14:30:00Z')
    refute SmartSuite::DateTransformer.date_only?('2025-06-20 14:30')
    refute SmartSuite::DateTransformer.date_only?('not a date')
  end

  def test_datetime_pattern
    assert SmartSuite::DateTransformer.datetime?('2025-06-20T14:30:00Z')
    assert SmartSuite::DateTransformer.datetime?('2025-06-20T14:30:00')
    assert SmartSuite::DateTransformer.datetime?('2025-06-20T14:30:00-07:00')
    assert SmartSuite::DateTransformer.datetime?('2025-06-20T14:30:00+05:30')
    assert SmartSuite::DateTransformer.datetime?('2025-06-20 14:30')
    assert SmartSuite::DateTransformer.datetime?('2025-06-20 14:30:00')
    refute SmartSuite::DateTransformer.datetime?('2025-06-20')
    refute SmartSuite::DateTransformer.datetime?('not a date')
  end

  def test_looks_like_date
    assert SmartSuite::DateTransformer.looks_like_date?('2025-06-20')
    assert SmartSuite::DateTransformer.looks_like_date?('2025/06/20')
    assert SmartSuite::DateTransformer.looks_like_date?('2025-06-20T14:30:00Z')
    assert SmartSuite::DateTransformer.looks_like_date?('2025-06-20 14:30')
    refute SmartSuite::DateTransformer.looks_like_date?('not a date')
    refute SmartSuite::DateTransformer.looks_like_date?(nil)
    refute SmartSuite::DateTransformer.looks_like_date?(123)
  end

  # ===================
  # Date String Transformation Tests
  # ===================

  def test_transform_date_only_string
    result = SmartSuite::DateTransformer.transform_date_string('2025-06-20')

    assert_equal({ 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }, result)
  end

  def test_transform_date_with_slashes
    result = SmartSuite::DateTransformer.transform_date_string('2025/06/20')

    assert_equal({ 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }, result)
  end

  def test_transform_datetime_utc
    result = SmartSuite::DateTransformer.transform_date_string('2025-06-20T14:30:00Z')

    assert_equal({ 'date' => '2025-06-20T14:30:00Z', 'include_time' => true }, result)
  end

  def test_transform_datetime_no_timezone
    result = SmartSuite::DateTransformer.transform_date_string('2025-06-20T14:30:00')

    assert_equal({ 'date' => '2025-06-20T14:30:00Z', 'include_time' => true }, result)
  end

  def test_transform_datetime_space_separated
    result = SmartSuite::DateTransformer.transform_date_string('2025-06-20 14:30')

    assert_equal({ 'date' => '2025-06-20T14:30:00Z', 'include_time' => true }, result)
  end

  def test_transform_datetime_space_separated_with_seconds
    result = SmartSuite::DateTransformer.transform_date_string('2025-06-20 14:30:45')

    assert_equal({ 'date' => '2025-06-20T14:30:45Z', 'include_time' => true }, result)
  end

  def test_transform_non_date_string
    result = SmartSuite::DateTransformer.transform_date_string('not a date')

    assert_equal 'not a date', result
  end

  def test_transform_nil
    result = SmartSuite::DateTransformer.transform_date_string(nil)

    assert_nil result
  end

  # ===================
  # Timezone Conversion Tests
  # ===================

  def test_normalize_datetime_utc
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20T14:30:00Z')

    assert_equal '2025-06-20T14:30:00Z', result
  end

  def test_normalize_datetime_pacific_time
    # PDT is UTC-7, so 14:30 PDT = 21:30 UTC
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20T14:30:00-07:00')

    assert_equal '2025-06-20T21:30:00Z', result
  end

  def test_normalize_datetime_india_time
    # IST is UTC+5:30, so 14:30 IST = 09:00 UTC
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20T14:30:00+05:30')

    assert_equal '2025-06-20T09:00:00Z', result
  end

  def test_normalize_datetime_japan_time
    # JST is UTC+9, so 23:00 JST = 14:00 UTC
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20T23:00:00+09:00')

    assert_equal '2025-06-20T14:00:00Z', result
  end

  def test_normalize_datetime_crossing_day_boundary
    # 5 PM PDT on July 4 = midnight UTC on July 5
    result = SmartSuite::DateTransformer.normalize_datetime('2025-07-04T17:00:00-07:00')

    assert_equal '2025-07-05T00:00:00Z', result
  end

  def test_normalize_datetime_no_timezone_assumes_utc
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20T14:30:00')

    assert_equal '2025-06-20T14:30:00Z', result
  end

  def test_normalize_datetime_space_format
    result = SmartSuite::DateTransformer.normalize_datetime('2025-06-20 14:30')

    assert_equal '2025-06-20T14:30:00Z', result
  end

  def test_convert_to_utc
    result = SmartSuite::DateTransformer.convert_to_utc('2025-06-20T14:30:00-07:00')

    assert_equal '2025-06-20T21:30:00Z', result
  end

  # ===================
  # Full Data Transformation Tests
  # ===================

  def test_transform_dates_simple_date_field
    data = { 'fecha' => '2025-06-20' }
    result = SmartSuite::DateTransformer.transform_dates(data)

    expected = {
      'fecha' => { 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }
    }
    assert_equal expected, result
  end

  def test_transform_dates_simple_datetime_field
    data = { 'fecha' => '2025-06-20T14:30:00Z' }
    result = SmartSuite::DateTransformer.transform_dates(data)

    expected = {
      'fecha' => { 'date' => '2025-06-20T14:30:00Z', 'include_time' => true }
    }
    assert_equal expected, result
  end

  def test_transform_dates_due_date_structure
    data = {
      'due_date' => {
        'from_date' => '2025-06-20',
        'to_date' => '2025-06-25T17:00:00Z'
      }
    }
    result = SmartSuite::DateTransformer.transform_dates(data)

    expected = {
      'due_date' => {
        'from_date' => { 'date' => '2025-06-20T00:00:00Z', 'include_time' => false },
        'to_date' => { 'date' => '2025-06-25T17:00:00Z', 'include_time' => true }
      }
    }
    assert_equal expected, result
  end

  def test_transform_dates_with_timezone_offset
    data = {
      'due_date' => {
        'from_date' => '2025-06-20T17:00:00-07:00',
        'to_date' => '2025-06-25'
      }
    }
    result = SmartSuite::DateTransformer.transform_dates(data)

    expected = {
      'due_date' => {
        'from_date' => { 'date' => '2025-06-21T00:00:00Z', 'include_time' => true },
        'to_date' => { 'date' => '2025-06-25T00:00:00Z', 'include_time' => false }
      }
    }
    assert_equal expected, result
  end

  def test_transform_dates_preserves_non_date_fields
    data = {
      'title' => 'Test Record',
      'status' => 'active',
      'due_date' => { 'from_date' => '2025-06-20' }
    }
    result = SmartSuite::DateTransformer.transform_dates(data)

    assert_equal 'Test Record', result['title']
    assert_equal 'active', result['status']
    assert_equal({ 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }, result['due_date']['from_date'])
  end

  def test_transform_dates_already_formatted
    # Already in SmartSuite format - should pass through
    data = {
      'due_date' => {
        'from_date' => { 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }
      }
    }
    result = SmartSuite::DateTransformer.transform_dates(data)

    expected = {
      'due_date' => {
        'from_date' => { 'date' => '2025-06-20T00:00:00Z', 'include_time' => false }
      }
    }
    assert_equal expected, result
  end

  def test_transform_dates_mixed_formats
    data = {
      'fecha' => '2025-09-10',
      'due_date' => {
        'from_date' => '2025-08-15T09:00:00Z',
        'to_date' => '2025-08-20'
      },
      's31437fa81' => {
        'from_date' => '2025-10-01T08:30:00Z',
        'to_date' => '2025-10-15'
      }
    }
    result = SmartSuite::DateTransformer.transform_dates(data)

    assert_equal false, result['fecha']['include_time']
    assert_equal true, result['due_date']['from_date']['include_time']
    assert_equal false, result['due_date']['to_date']['include_time']
    assert_equal true, result['s31437fa81']['from_date']['include_time']
    assert_equal false, result['s31437fa81']['to_date']['include_time']
  end

  # ===================
  # Edge Cases
  # ===================

  def test_transform_empty_hash
    result = SmartSuite::DateTransformer.transform_dates({})

    assert_equal({}, result)
  end

  def test_transform_nil_value
    result = SmartSuite::DateTransformer.transform_dates(nil)

    assert_nil result
  end

  def test_date_structure_detection
    assert SmartSuite::DateTransformer.date_structure?({ 'from_date' => '2025-06-20' })
    assert SmartSuite::DateTransformer.date_structure?({ 'to_date' => '2025-06-20' })
    assert SmartSuite::DateTransformer.date_structure?({ 'date' => '2025-06-20' })
    assert SmartSuite::DateTransformer.date_structure?({ 'include_time' => true })
    refute SmartSuite::DateTransformer.date_structure?({ 'title' => 'Test' })
    refute SmartSuite::DateTransformer.date_structure?(nil)
  end

  def test_midnight_utc_detection
    assert SmartSuite::DateTransformer.midnight_utc?('2025-06-20T00:00:00Z')
    assert SmartSuite::DateTransformer.midnight_utc?('2025-06-20T00:00:00')
    refute SmartSuite::DateTransformer.midnight_utc?('2025-06-20T14:30:00Z')
    refute SmartSuite::DateTransformer.midnight_utc?('2025-06-20')
  end
end
