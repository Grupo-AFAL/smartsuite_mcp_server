# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite/api/base'

class TestApiBase < Minitest::Test
  # Test class that includes Base module
  class TestClass
    include SmartSuite::API::Base

    attr_accessor :cache_enabled

    def initialize
      @cache_enabled = false
    end

    def cache_enabled?
      @cache_enabled
    end

    def log_metric(message)
      @logged_messages ||= []
      @logged_messages << message
    end

    def log_token_usage(tokens)
      @logged_tokens ||= []
      @logged_tokens << tokens
    end

    def estimate_tokens(json_str)
      json_str.length / 4 # Simple estimation
    end

    attr_reader :logged_messages, :logged_tokens
  end

  def setup
    @test_obj = TestClass.new
  end

  # Test pagination constants
  def test_pagination_constants
    assert_equal 100, SmartSuite::API::Base::Pagination::DEFAULT_LIMIT
    assert_equal 1000, SmartSuite::API::Base::Pagination::FETCH_ALL_LIMIT
    assert_equal 1000, SmartSuite::API::Base::Pagination::MAX_LIMIT
    assert_equal 0, SmartSuite::API::Base::Pagination::DEFAULT_OFFSET
  end

  # Test validate_required_parameter!
  def test_validate_required_parameter_with_valid_value
    assert_equal 'value', @test_obj.validate_required_parameter!('param', 'value')
  end

  def test_validate_required_parameter_with_nil
    error = assert_raises(ArgumentError) do
      @test_obj.validate_required_parameter!('param', nil)
    end
    assert_equal 'param is required and cannot be nil or empty', error.message
  end

  def test_validate_required_parameter_with_empty_string
    error = assert_raises(ArgumentError) do
      @test_obj.validate_required_parameter!('param', '')
    end
    assert_equal 'param is required and cannot be nil or empty', error.message
  end

  def test_validate_required_parameter_with_empty_array
    error = assert_raises(ArgumentError) do
      @test_obj.validate_required_parameter!('param', [])
    end
    assert_equal 'param is required and cannot be nil or empty', error.message
  end

  def test_validate_required_parameter_with_type_constraint
    assert_equal [1, 2, 3], @test_obj.validate_required_parameter!('list', [1, 2, 3], Array)
  end

  def test_validate_required_parameter_with_wrong_type
    error = assert_raises(ArgumentError) do
      @test_obj.validate_required_parameter!('list', 'not_array', Array)
    end
    assert_equal 'list must be a Array, got String', error.message
  end

  # Test validate_optional_parameter!
  def test_validate_optional_parameter_with_nil
    assert_nil @test_obj.validate_optional_parameter!('param', nil, String)
  end

  def test_validate_optional_parameter_with_correct_type
    assert_equal 'value', @test_obj.validate_optional_parameter!('param', 'value', String)
    assert_equal [1, 2], @test_obj.validate_optional_parameter!('list', [1, 2], Array)
  end

  def test_validate_optional_parameter_with_wrong_type
    error = assert_raises(ArgumentError) do
      @test_obj.validate_optional_parameter!('list', 'not_array', Array)
    end
    assert_equal 'list must be a Array, got String', error.message
  end

  # Test build_endpoint
  def test_build_endpoint_without_params
    assert_equal '/solutions/', @test_obj.build_endpoint('/solutions/')
  end

  def test_build_endpoint_with_empty_params
    assert_equal '/solutions/', @test_obj.build_endpoint('/solutions/', **{})
  end

  def test_build_endpoint_with_single_param
    result = @test_obj.build_endpoint('/solutions/', limit: 100)
    assert_equal '/solutions/?limit=100', result
  end

  def test_build_endpoint_with_multiple_params
    result = @test_obj.build_endpoint('/solutions/', limit: 100, offset: 50)
    assert_includes result, 'limit=100'
    assert_includes result, 'offset=50'
    assert_match %r{^/solutions/\?}, result
  end

  def test_build_endpoint_with_array_param
    result = @test_obj.build_endpoint('/applications/', fields: %w[id name status])
    assert_equal '/applications/?fields=id&fields=name&fields=status', result
  end

  def test_build_endpoint_with_mixed_params
    result = @test_obj.build_endpoint('/applications/', solution: 'sol_123', fields: %w[id name])
    assert_includes result, 'solution=sol_123'
    assert_includes result, 'fields=id&fields=name'
  end

  def test_build_endpoint_with_url_encoding
    result = @test_obj.build_endpoint('/comments/', record: 'rec_abc%123')
    assert_equal '/comments/?record=rec_abc%25123', result
  end

  def test_build_endpoint_filters_nil_values
    result = @test_obj.build_endpoint('/solutions/', limit: 100, offset: nil)
    assert_equal '/solutions/?limit=100', result
  end

  def test_build_endpoint_filters_empty_arrays
    result = @test_obj.build_endpoint('/solutions/', limit: 100, fields: [])
    assert_equal '/solutions/?limit=100', result
  end

  def test_build_endpoint_with_boolean_params
    result = @test_obj.build_endpoint('/records/', hydrated: true)
    assert_equal '/records/?hydrated=true', result
  end

  # Test should_bypass_cache?
  def test_should_bypass_cache_when_cache_disabled
    @test_obj.cache_enabled = false
    assert @test_obj.should_bypass_cache?(bypass: false)
  end

  def test_should_bypass_cache_when_bypass_true
    @test_obj.cache_enabled = true
    assert @test_obj.should_bypass_cache?(bypass: true)
  end

  def test_should_not_bypass_cache_when_enabled_and_not_bypassed
    @test_obj.cache_enabled = true
    refute @test_obj.should_bypass_cache?(bypass: false)
  end

  # Test track_response_size
  def test_track_response_size
    result = { 'data' => 'test value' * 100 }
    returned = @test_obj.track_response_size(result, 'Found 10 items')

    # Should return the original result
    assert_equal result, returned

    # Should log success message with checkmark
    assert_equal ['✓ Found 10 items'], @test_obj.logged_messages

    # Should log token count (rough estimate)
    refute_empty @test_obj.logged_tokens
    assert_kind_of Integer, @test_obj.logged_tokens.first
  end

  # Test build_collection_response
  def test_build_collection_response_basic
    items = [{ 'id' => 1 }, { 'id' => 2 }]
    result = @test_obj.build_collection_response(items, :solutions)

    assert_equal items, result['solutions']
    assert_equal 2, result['count']
  end

  def test_build_collection_response_with_metadata
    items = [{ 'id' => 1 }, { 'id' => 2 }]
    result = @test_obj.build_collection_response(items, :members, total_count: 100, filtered: true)

    assert_equal items, result['members']
    assert_equal 2, result['count']
    assert_equal 100, result['total_count']
    assert_equal true, result['filtered']
  end

  def test_build_collection_response_with_string_key
    items = [{ 'id' => 1 }]
    result = @test_obj.build_collection_response(items, 'solutions')

    assert_equal items, result['solutions']
  end

  def test_build_collection_response_with_empty_array
    result = @test_obj.build_collection_response([], :solutions)

    assert_equal [], result['solutions']
    assert_equal 0, result['count']
  end

  # Test extract_items_from_response
  def test_extract_items_from_response_with_valid_response
    response = { 'items' => [{ 'id' => 1 }, { 'id' => 2 }] }
    items = @test_obj.extract_items_from_response(response)

    assert_equal 2, items.size
    assert_equal 1, items.first['id']
  end

  def test_extract_items_from_response_with_nil
    assert_equal [], @test_obj.extract_items_from_response(nil)
  end

  def test_extract_items_from_response_with_empty_hash
    assert_equal [], @test_obj.extract_items_from_response({})
  end

  def test_extract_items_from_response_with_wrong_structure
    response = { 'items' => 'not_an_array' }
    assert_equal [], @test_obj.extract_items_from_response(response)
  end

  def test_extract_items_from_response_with_custom_key
    response = { 'data' => [{ 'id' => 1 }] }
    items = @test_obj.extract_items_from_response(response, 'data')

    assert_equal 1, items.size
  end

  # Test format_timestamp
  def test_format_timestamp
    time = Time.new(2025, 1, 16, 10, 30, 45)
    result = @test_obj.format_timestamp(time)

    assert_match(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/, result)
    assert_includes result, '2025-01-16'
  end

  def test_format_timestamp_with_default
    result = @test_obj.format_timestamp
    assert_match(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/, result)
  end

  # Test log_cache_hit
  def test_log_cache_hit_without_key
    @test_obj.log_cache_hit('solutions', 110)
    assert_equal ['✓ Cache hit: 110 solutions'], @test_obj.logged_messages
  end

  def test_log_cache_hit_with_key
    @test_obj.log_cache_hit('tables', 25, 'sol_abc123')
    assert_equal ['✓ Cache hit: 25 tables (sol_abc123)'], @test_obj.logged_messages
  end

  # Test log_cache_miss
  def test_log_cache_miss_without_key
    @test_obj.log_cache_miss('solutions')
    assert_equal ['→ Cache miss for solutions, fetching from API...'], @test_obj.logged_messages
  end

  def test_log_cache_miss_with_key
    @test_obj.log_cache_miss('tables', 'sol_abc123')
    assert_equal ['→ Cache miss for tables (sol_abc123), fetching from API...'], @test_obj.logged_messages
  end

  # Edge cases
  def test_build_endpoint_with_numeric_values
    result = @test_obj.build_endpoint('/records/', limit: 100, priority: 5)
    assert_includes result, 'limit=100'
    assert_includes result, 'priority=5'
  end

  def test_build_endpoint_with_special_characters
    result = @test_obj.build_endpoint('/search/', query: 'hello world & test')
    assert_includes result, 'query=hello+world+%26+test'
  end

  def test_validate_required_parameter_with_zero
    # Zero should be valid (not empty)
    assert_equal 0, @test_obj.validate_required_parameter!('count', 0)
  end

  def test_validate_required_parameter_with_false
    # False should be valid (not empty)
    assert_equal false, @test_obj.validate_required_parameter!('flag', false)
  end

  def test_build_collection_response_preserves_metadata_types
    items = [{ 'id' => 1 }]
    result = @test_obj.build_collection_response(items, :data, numeric: 123, string: 'abc', bool: true)

    assert_equal 123, result['numeric']
    assert_equal 'abc', result['string']
    assert_equal true, result['bool']
  end

  # Test with_cache_check
  def test_with_cache_check_returns_nil_when_cache_disabled
    @test_obj.cache_enabled = false
    result = @test_obj.with_cache_check('solutions') { ['cached_data'] }

    assert_nil result
  end

  def test_with_cache_check_returns_nil_when_bypassed
    @test_obj.cache_enabled = true
    result = @test_obj.with_cache_check('solutions', nil, bypass: true) { ['cached_data'] }

    assert_nil result
  end

  def test_with_cache_check_returns_cached_data_on_hit
    @test_obj.cache_enabled = true
    cached_data = [{ 'id' => 1 }, { 'id' => 2 }]
    result = @test_obj.with_cache_check('solutions') { cached_data }

    assert_equal cached_data, result
    assert_includes @test_obj.logged_messages.first, 'Cache hit: 2 solutions'
  end

  def test_with_cache_check_logs_cache_key_on_hit
    @test_obj.cache_enabled = true
    result = @test_obj.with_cache_check('tables', 'sol_123') { [{ 'id' => 1 }] }

    assert_equal [{ 'id' => 1 }], result
    assert_includes @test_obj.logged_messages.first, 'sol_123'
  end

  def test_with_cache_check_returns_nil_on_cache_miss
    @test_obj.cache_enabled = true
    result = @test_obj.with_cache_check('solutions') { nil }

    assert_nil result
    assert_includes @test_obj.logged_messages.first, 'Cache miss'
  end

  def test_with_cache_check_handles_single_item_cache
    @test_obj.cache_enabled = true
    single_item = { 'id' => 1 }
    result = @test_obj.with_cache_check('record') { single_item }

    assert_equal single_item, result
    assert_includes @test_obj.logged_messages.first, 'Cache hit: 1 record'
  end

  # Test extract_items_safely
  def test_extract_items_safely_with_array
    data = [{ 'id' => 1 }, { 'id' => 2 }]
    result = @test_obj.extract_items_safely(data)

    assert_equal data, result
  end

  def test_extract_items_safely_with_hash_containing_items
    data = { 'items' => [{ 'id' => 1 }, { 'id' => 2 }], 'count' => 2 }
    result = @test_obj.extract_items_safely(data)

    assert_equal [{ 'id' => 1 }, { 'id' => 2 }], result
  end

  def test_extract_items_safely_with_custom_key
    data = { 'data' => [{ 'id' => 1 }] }
    result = @test_obj.extract_items_safely(data, 'data')

    assert_equal [{ 'id' => 1 }], result
  end

  def test_extract_items_safely_with_empty_hash
    result = @test_obj.extract_items_safely({})

    assert_equal [], result
  end

  def test_extract_items_safely_with_nil
    result = @test_obj.extract_items_safely(nil)

    assert_equal [], result
  end
end
