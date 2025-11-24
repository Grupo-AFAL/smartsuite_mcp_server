# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/smartsuite/date_formatter'

class TestDateFormatter < Minitest::Test
  def setup
    # Reset timezone configuration before each test
    SmartSuite::DateFormatter.reset_timezone!
    # Clear environment variable
    @original_env = ENV.fetch('SMARTSUITE_TIMEZONE', nil)
    ENV.delete('SMARTSUITE_TIMEZONE')
  end

  def teardown
    # Restore original state
    SmartSuite::DateFormatter.reset_timezone!
    if @original_env
      ENV['SMARTSUITE_TIMEZONE'] = @original_env
    else
      ENV.delete('SMARTSUITE_TIMEZONE')
    end
  end

  # ============ Timestamp Detection Tests ============

  def test_timestamp_detection_full_iso8601_with_z
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30:00Z')
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30:00.123Z')
    assert SmartSuite::DateFormatter.timestamp?('2025-12-31T23:59:59Z')
  end

  def test_timestamp_detection_with_offset
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30:00+00:00')
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30:00-05:00')
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30:00+0530')
  end

  def test_timestamp_detection_date_only
    assert SmartSuite::DateFormatter.timestamp?('2025-01-15')
    assert SmartSuite::DateFormatter.timestamp?('2020-12-31')
  end

  def test_timestamp_detection_non_timestamps
    refute SmartSuite::DateFormatter.timestamp?('hello')
    refute SmartSuite::DateFormatter.timestamp?('12345')
    refute SmartSuite::DateFormatter.timestamp?('2025-1-15') # Invalid format
    refute SmartSuite::DateFormatter.timestamp?('01-15-2025') # Wrong order
    refute SmartSuite::DateFormatter.timestamp?(nil)
    refute SmartSuite::DateFormatter.timestamp?(123)
  end

  def test_timestamp_detection_edge_cases
    refute SmartSuite::DateFormatter.timestamp?('')
    refute SmartSuite::DateFormatter.timestamp?('   ')
    refute SmartSuite::DateFormatter.timestamp?('2025-01-15T') # Incomplete
    refute SmartSuite::DateFormatter.timestamp?('2025-01-15T10:30') # Missing seconds
  end

  # ============ Date-Only Detection Tests ============

  def test_date_only_detection
    assert SmartSuite::DateFormatter.date_only?('2025-01-15')
    refute SmartSuite::DateFormatter.date_only?('2025-01-15T10:30:00Z')
    refute SmartSuite::DateFormatter.date_only?('not-a-date')
  end

  # ============ UTC Mode Tests ============

  def test_utc_mode_returns_original
    SmartSuite::DateFormatter.timezone = :utc
    timestamp = '2025-01-15T10:30:00Z'
    assert_equal timestamp, SmartSuite::DateFormatter.to_local(timestamp)
  end

  def test_utc_mode_via_environment
    ENV['SMARTSUITE_TIMEZONE'] = 'utc'
    timestamp = '2025-01-15T10:30:00Z'
    assert_equal timestamp, SmartSuite::DateFormatter.to_local(timestamp)
  end

  def test_utc_mode_case_insensitive
    ENV['SMARTSUITE_TIMEZONE'] = 'UTC'
    timestamp = '2025-01-15T10:30:00Z'
    assert_equal timestamp, SmartSuite::DateFormatter.to_local(timestamp)
  end

  # ============ Explicit Timezone Offset Tests ============

  def test_explicit_offset_conversion
    SmartSuite::DateFormatter.timezone = '-0500'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    assert_equal '2025-01-15 05:30:00 -0500', result
  end

  def test_explicit_offset_with_colon
    SmartSuite::DateFormatter.timezone = '+05:30'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    assert_equal '2025-01-15 16:00:00 +0530', result
  end

  def test_explicit_offset_via_environment
    ENV['SMARTSUITE_TIMEZONE'] = '-0300'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    assert_equal '2025-01-15 07:30:00 -0300', result
  end

  # ============ System/Local Mode Tests ============

  def test_local_timezone_conversion
    # Use system local timezone (default)
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    # Result should include timezone offset and be different from UTC input
    assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}/, result)
    # Verify it's a valid time
    parsed = Time.parse(result)
    assert_equal 2025, parsed.year
    assert_equal 1, parsed.month
    assert_equal 15, parsed.day
  end

  def test_local_keyword_in_environment
    ENV['SMARTSUITE_TIMEZONE'] = 'local'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    # Should use system timezone
    assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}/, result)
  end

  def test_system_keyword_in_environment
    ENV['SMARTSUITE_TIMEZONE'] = 'system'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    # Should use system timezone
    assert_match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}/, result)
  end

  # ============ Date-Only Conversion Tests ============

  def test_date_only_stays_date_only
    # Date-only strings should remain date-only (no time component)
    SmartSuite::DateFormatter.timezone = '-0500'
    result = SmartSuite::DateFormatter.to_local('2025-01-15')
    assert_equal '2025-01-15', result
  end

  # ============ Non-Timestamp Passthrough Tests ============

  def test_non_timestamp_string_passthrough
    assert_equal 'hello', SmartSuite::DateFormatter.to_local('hello')
    assert_equal 'test@example.com', SmartSuite::DateFormatter.to_local('test@example.com')
  end

  def test_nil_passthrough
    assert_nil SmartSuite::DateFormatter.to_local(nil)
  end

  def test_non_string_passthrough
    assert_equal 123, SmartSuite::DateFormatter.to_local(123)
    assert_equal true, SmartSuite::DateFormatter.to_local(true)
  end

  # ============ Convert All (Recursive) Tests ============

  def test_convert_all_simple_hash
    SmartSuite::DateFormatter.timezone = '-0500'
    data = { 'created' => '2025-01-15T10:30:00Z', 'name' => 'Test' }
    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-01-15 05:30:00 -0500', result['created']
    assert_equal 'Test', result['name']
  end

  def test_convert_all_nested_hash
    SmartSuite::DateFormatter.timezone = '-0500'
    data = {
      'record' => {
        'created' => '2025-01-15T10:30:00Z',
        'updated' => '2025-01-16T15:00:00Z'
      },
      'count' => 5
    }
    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-01-15 05:30:00 -0500', result['record']['created']
    assert_equal '2025-01-16 10:00:00 -0500', result['record']['updated']
    assert_equal 5, result['count']
  end

  def test_convert_all_array
    SmartSuite::DateFormatter.timezone = '-0500'
    data = ['2025-01-15T10:30:00Z', '2025-01-16T10:30:00Z', 'text']
    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-01-15 05:30:00 -0500', result[0]
    assert_equal '2025-01-16 05:30:00 -0500', result[1]
    assert_equal 'text', result[2]
  end

  def test_convert_all_mixed_structure
    SmartSuite::DateFormatter.timezone = '-0500'
    data = {
      'items' => [
        { 'date' => '2025-01-15T10:30:00Z' },
        { 'date' => '2025-01-16T10:30:00Z' }
      ]
    }
    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-01-15 05:30:00 -0500', result['items'][0]['date']
    assert_equal '2025-01-16 05:30:00 -0500', result['items'][1]['date']
  end

  # ============ Timezone Info Tests ============

  def test_timezone_info
    SmartSuite::DateFormatter.timezone = '-0300'
    info = SmartSuite::DateFormatter.timezone_info

    assert_equal '-0300', info['configured']
    assert_equal '-0300', info['effective']
    assert_match(/[+-]\d{4}/, info['current_offset'])
    assert info.key?('current_zone')
  end

  def test_timezone_info_with_environment
    ENV['SMARTSUITE_TIMEZONE'] = '+0530'
    info = SmartSuite::DateFormatter.timezone_info

    assert_nil info['configured']
    assert_equal '+0530', info['environment']
    assert_equal '+0530', info['effective']
  end

  def test_timezone_info_default
    info = SmartSuite::DateFormatter.timezone_info

    assert_nil info['configured']
    assert_nil info['environment']
    assert_equal 'system', info['effective']
  end

  # ============ Configuration Priority Tests ============

  def test_programmatic_overrides_environment
    ENV['SMARTSUITE_TIMEZONE'] = '-0300'
    SmartSuite::DateFormatter.timezone = '-0500'

    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
    assert_equal '2025-01-15 05:30:00 -0500', result
  end

  def test_reset_timezone
    SmartSuite::DateFormatter.timezone = '-0500'
    SmartSuite::DateFormatter.reset_timezone!

    # After reset, should use system timezone
    info = SmartSuite::DateFormatter.timezone_info
    assert_nil info['configured']
    assert_equal 'system', info['effective']
  end

  # ============ Edge Cases ============

  def test_invalid_timestamp_passthrough
    result = SmartSuite::DateFormatter.to_local('2025-13-45T99:99:99Z')
    # Invalid timestamp should pass through unchanged
    assert_equal '2025-13-45T99:99:99Z', result
  end

  def test_empty_string_passthrough
    result = SmartSuite::DateFormatter.to_local('')
    assert_equal '', result
  end

  def test_milliseconds_preserved_in_conversion
    SmartSuite::DateFormatter.timezone = '-0500'
    result = SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00.123Z')
    # Milliseconds are not included in output format, but conversion should still work
    assert_equal '2025-01-15 05:30:00 -0500', result
  end

  # ============ Include Time Flag Tests ============

  def test_date_hash_with_include_time_false
    # Date-only field: include_time is false
    # Should NOT convert timezone - just return the UTC date
    SmartSuite::DateFormatter.timezone = '-0800' # Pacific time
    date_hash = { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false }

    result = SmartSuite::DateFormatter.to_local(date_hash)

    # Feb 1 should remain Feb 1 (not become Jan 31 due to timezone conversion)
    assert_equal '2025-02-01', result
  end

  def test_date_hash_with_include_time_true
    # Datetime field: include_time is true
    # Should convert to local timezone
    SmartSuite::DateFormatter.timezone = '-0800'
    date_hash = { 'date' => '2025-02-04T11:15:00Z', 'include_time' => true }

    result = SmartSuite::DateFormatter.to_local(date_hash)

    # 11:15 UTC should become 03:15 PST
    assert_equal '2025-02-04 03:15:00 -0800', result
  end

  def test_date_hash_with_symbol_keys
    SmartSuite::DateFormatter.timezone = '-0500'
    date_hash = { date: '2025-01-15T10:30:00Z', include_time: true }

    result = SmartSuite::DateFormatter.to_local(date_hash)

    assert_equal '2025-01-15 05:30:00 -0500', result
  end

  def test_date_hash_detection
    date_hash = { 'date' => '2025-01-15T00:00:00Z', 'include_time' => false }
    non_date_hash = { 'name' => 'Test', 'value' => 123 }

    assert SmartSuite::DateFormatter.date_hash?(date_hash)
    refute SmartSuite::DateFormatter.date_hash?(non_date_hash)
  end

  def test_convert_all_with_date_hashes
    SmartSuite::DateFormatter.timezone = '-0800'
    data = {
      'date_only' => { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false },
      'datetime' => { 'date' => '2025-02-04T11:15:00Z', 'include_time' => true },
      'name' => 'Test'
    }

    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-02-01', result['date_only']
    assert_equal '2025-02-04 03:15:00 -0800', result['datetime']
    assert_equal 'Test', result['name']
  end

  def test_convert_all_preserves_nested_date_hashes
    SmartSuite::DateFormatter.timezone = '-0800'
    data = {
      'record' => {
        'due_date' => { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false },
        'created' => '2025-01-15T10:30:00Z'
      }
    }

    result = SmartSuite::DateFormatter.convert_all(data)

    assert_equal '2025-02-01', result['record']['due_date']
    assert_equal '2025-01-15 02:30:00 -0800', result['record']['created']
  end

  def test_date_hash_utc_mode
    SmartSuite::DateFormatter.timezone = :utc
    date_hash = { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false }

    result = SmartSuite::DateFormatter.to_local(date_hash)

    # In UTC mode, original timestamp is returned unchanged
    assert_equal '2025-02-01T00:00:00Z', result
  end

  def test_date_hash_with_nil_date
    date_hash = { 'date' => nil, 'include_time' => false }

    result = SmartSuite::DateFormatter.to_local(date_hash)

    assert_nil result
  end

  # ============ Named Timezone Tests ============

  def test_named_timezone_detection
    assert SmartSuite::DateFormatter.named_timezone?('America/Mexico_City')
    assert SmartSuite::DateFormatter.named_timezone?('Europe/London')
    assert SmartSuite::DateFormatter.named_timezone?('Asia/Tokyo')
    assert SmartSuite::DateFormatter.named_timezone?('America/Argentina/Buenos_Aires')

    refute SmartSuite::DateFormatter.named_timezone?('-0500')
    refute SmartSuite::DateFormatter.named_timezone?('+05:30')
    refute SmartSuite::DateFormatter.named_timezone?('UTC')
    refute SmartSuite::DateFormatter.named_timezone?('local')
    refute SmartSuite::DateFormatter.named_timezone?(nil)
    refute SmartSuite::DateFormatter.named_timezone?(123)
  end

  def test_named_timezone_configuration
    SmartSuite::DateFormatter.timezone = 'America/Mexico_City'

    assert_equal 'America/Mexico_City', SmartSuite::DateFormatter.timezone

    info = SmartSuite::DateFormatter.timezone_info
    assert_equal 'America/Mexico_City', info['configured']
    assert_equal 'named', info['type']
  end

  def test_named_timezone_conversion
    SmartSuite::DateFormatter.timezone = 'America/New_York'

    result = SmartSuite::DateFormatter.to_local('2025-01-15T15:00:00Z')

    # January 15 is in EST (-0500)
    # 15:00 UTC = 10:00 EST
    assert_match(/2025-01-15 10:00:00 -0500/, result)
  end

  def test_named_timezone_with_dst
    SmartSuite::DateFormatter.timezone = 'America/New_York'

    # July is in EDT (-0400)
    result = SmartSuite::DateFormatter.to_local('2025-07-15T15:00:00Z')

    # 15:00 UTC = 11:00 EDT
    assert_match(/2025-07-15 11:00:00 -0400/, result)
  end

  def test_named_timezone_via_environment
    ENV['SMARTSUITE_TIMEZONE'] = 'America/Los_Angeles'

    result = SmartSuite::DateFormatter.to_local('2025-01-15T20:00:00Z')

    # January is PST (-0800)
    # 20:00 UTC = 12:00 PST
    assert_match(/2025-01-15 12:00:00 -0800/, result)
  end

  def test_named_timezone_with_include_time_flag
    SmartSuite::DateFormatter.timezone = 'America/Mexico_City'

    date_hash = { 'date' => '2025-02-04T11:15:00Z', 'include_time' => true }
    result = SmartSuite::DateFormatter.to_local(date_hash)

    # February 4 in Mexico City is CST (-0600)
    # 11:15 UTC = 05:15 CST
    assert_match(/2025-02-04 05:15:00 -0600/, result)
  end

  def test_named_timezone_date_only_not_converted
    SmartSuite::DateFormatter.timezone = 'America/Mexico_City'

    # Date-only with include_time: false should NOT convert timezone
    date_hash = { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false }
    result = SmartSuite::DateFormatter.to_local(date_hash)

    # Should stay Feb 1, not become Jan 31
    assert_equal '2025-02-01', result
  end

  def test_timezone_info_type_indicators
    # Test UTC type
    SmartSuite::DateFormatter.timezone = :utc
    assert_equal 'utc', SmartSuite::DateFormatter.timezone_info['type']

    # Test offset type
    SmartSuite::DateFormatter.timezone = '-0500'
    assert_equal 'offset', SmartSuite::DateFormatter.timezone_info['type']

    # Test named type
    SmartSuite::DateFormatter.timezone = 'America/New_York'
    assert_equal 'named', SmartSuite::DateFormatter.timezone_info['type']

    # Test system type
    SmartSuite::DateFormatter.reset_timezone!
    assert_equal 'system', SmartSuite::DateFormatter.timezone_info['type']
  end

  # ============ Smart Midnight Detection Tests ============

  def test_midnight_utc_detection
    # Midnight UTC
    midnight_time = Time.parse('2025-02-01T00:00:00Z')
    assert SmartSuite::DateFormatter.midnight_utc?(midnight_time)

    # Non-midnight UTC
    afternoon_time = Time.parse('2025-02-01T11:15:00Z')
    refute SmartSuite::DateFormatter.midnight_utc?(afternoon_time)

    # Near midnight but not exactly
    near_midnight = Time.parse('2025-02-01T00:00:01Z')
    refute SmartSuite::DateFormatter.midnight_utc?(near_midnight)
  end

  def test_smart_detection_non_midnight_always_datetime
    SmartSuite::DateFormatter.timezone = '-0800'

    # Non-midnight UTC should ALWAYS be treated as datetime
    # even if include_time is false (SmartSuite API bug workaround)
    date_hash = { 'date' => '2025-02-04T11:15:00Z', 'include_time' => false }
    result = SmartSuite::DateFormatter.to_local(date_hash)

    # Should convert timezone because it's not midnight
    assert_match(/2025-02-04 03:15:00 -0800/, result)
  end

  def test_smart_detection_midnight_trusts_include_time
    SmartSuite::DateFormatter.timezone = '-0800'

    # Midnight UTC with include_time: false -> date only
    date_hash_false = { 'date' => '2025-02-01T00:00:00Z', 'include_time' => false }
    result_false = SmartSuite::DateFormatter.to_local(date_hash_false)
    assert_equal '2025-02-01', result_false

    # Midnight UTC with include_time: true -> datetime
    date_hash_true = { 'date' => '2025-02-01T00:00:00Z', 'include_time' => true }
    result_true = SmartSuite::DateFormatter.to_local(date_hash_true)
    # Midnight UTC -> 4pm previous day in PST
    assert_match(/2025-01-31 16:00:00 -0800/, result_true)
  end
end
