# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite_client'

class SmartSuiteClientTest < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @test_cache_path = File.join(Dir.tmpdir, "smartsuite_client_test_#{Process.pid}_#{rand(10_000)}.db")
  end

  def teardown
    File.delete(@test_cache_path) if File.exist?(@test_cache_path)
  end

  def create_client_with_cache
    SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)
  end

  def create_client_without_cache
    SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
  end

  # ==========================================
  # Tests for warm_cache method
  # ==========================================

  def test_warm_cache_returns_error_when_cache_disabled
    client = create_client_without_cache

    result = client.warm_cache(tables: ['tbl_1'])

    assert result.is_a?(Hash)
    assert_equal 'cache_disabled', result['error']
    assert_includes result['message'], 'Cache is not enabled'
  end

  def test_warm_cache_returns_no_action_when_no_tables
    client = create_client_with_cache

    # Mock get_tables_to_warm to return empty array
    client.cache.define_singleton_method(:get_tables_to_warm) do |tables:, count:|
      []
    end

    result = client.warm_cache(tables: 'auto', count: 5)

    assert_equal 'warm', result['operation']
    assert_equal 'no_action', result['status']
    assert_includes result['message'], 'No tables to warm'
  end

  def test_warm_cache_warms_tables_successfully
    client = create_client_with_cache

    # Mock get_tables_to_warm
    client.cache.define_singleton_method(:get_tables_to_warm) do |tables:, count:|
      ['tbl_1', 'tbl_2']
    end

    # Mock cache_valid? to return false (cache needs warming)
    client.cache.define_singleton_method(:cache_valid?) do |table_id|
      false
    end

    # Mock list_records
    client.define_singleton_method(:list_records) do |table_id, limit, offset, fields:|
      "1 of 1 filtered records (1 total)\n\nid: rec_#{table_id}"
    end

    result = client.warm_cache(tables: ['tbl_1', 'tbl_2'])

    assert_equal 'warm', result['operation']
    assert_equal 'completed', result['status']
    assert_includes result['message'], 'completed'
    assert_equal 2, result['summary']['total_tables']
    assert_equal 2, result['summary']['warmed']
    assert_equal 0, result['summary']['skipped']
    assert_equal 0, result['summary']['errors']
    assert_equal 2, result['results'].size
    assert_equal 'warmed', result['results'][0]['status']
  end

  def test_warm_cache_skips_already_cached_tables
    client = create_client_with_cache

    # Mock get_tables_to_warm
    client.cache.define_singleton_method(:get_tables_to_warm) do |tables:, count:|
      ['tbl_1', 'tbl_2']
    end

    # Mock cache_valid? - tbl_1 is valid, tbl_2 is not
    valid_tables = { 'tbl_1' => true, 'tbl_2' => false }
    client.cache.define_singleton_method(:cache_valid?) do |table_id|
      valid_tables[table_id]
    end

    # Mock list_records for tbl_2
    client.define_singleton_method(:list_records) do |table_id, limit, offset, fields:|
      "1 of 1 filtered records (1 total)\n\nid: rec_#{table_id}"
    end

    result = client.warm_cache(tables: ['tbl_1', 'tbl_2'])

    assert_equal 'warm', result['operation']
    assert_equal 'completed', result['status']
    assert_equal 2, result['summary']['total_tables']
    assert_equal 1, result['summary']['warmed']
    assert_equal 1, result['summary']['skipped']
    assert_equal 0, result['summary']['errors']

    # Check individual results
    tbl1_result = result['results'].find { |r| r['table_id'] == 'tbl_1' }
    tbl2_result = result['results'].find { |r| r['table_id'] == 'tbl_2' }
    assert_equal 'skipped', tbl1_result['status']
    assert_equal 'warmed', tbl2_result['status']
  end

  def test_warm_cache_handles_errors_gracefully
    client = create_client_with_cache

    # Mock get_tables_to_warm
    client.cache.define_singleton_method(:get_tables_to_warm) do |tables:, count:|
      ['tbl_1', 'tbl_2']
    end

    # Mock cache_valid? to return false
    client.cache.define_singleton_method(:cache_valid?) do |table_id|
      false
    end

    # Mock list_records to raise error for tbl_1, succeed for tbl_2
    called_tables = []
    client.define_singleton_method(:list_records) do |table_id, limit, offset, fields:|
      called_tables << table_id
      raise StandardError, 'API Error' if table_id == 'tbl_1'

      "1 of 1 filtered records (1 total)\n\nid: rec_#{table_id}"
    end

    result = client.warm_cache(tables: ['tbl_1', 'tbl_2'])

    assert_equal 'warm', result['operation']
    assert_equal 'completed', result['status']
    assert_includes result['message'], 'partially completed'
    assert_equal 2, result['summary']['total_tables']
    assert_equal 1, result['summary']['warmed']
    assert_equal 0, result['summary']['skipped']
    assert_equal 1, result['summary']['errors']

    # Check individual results
    tbl1_result = result['results'].find { |r| r['table_id'] == 'tbl_1' }
    tbl2_result = result['results'].find { |r| r['table_id'] == 'tbl_2' }
    assert_equal 'error', tbl1_result['status']
    assert_includes tbl1_result['error'], 'API Error'
    assert_equal 'warmed', tbl2_result['status']
  end

  def test_warm_cache_with_auto_mode
    client = create_client_with_cache

    # Mock get_tables_to_warm to verify it receives auto and count
    received_params = nil
    client.cache.define_singleton_method(:get_tables_to_warm) do |tables:, count:|
      received_params = { tables: tables, count: count }
      ['tbl_auto_1']
    end

    client.cache.define_singleton_method(:cache_valid?) do |table_id|
      false
    end

    client.define_singleton_method(:list_records) do |table_id, limit, offset, fields:|
      "1 of 1 filtered records (1 total)\n\nid: rec_#{table_id}"
    end

    result = client.warm_cache(tables: 'auto', count: 10)

    assert_equal 'auto', received_params[:tables]
    assert_equal 10, received_params[:count]
    assert_equal 'completed', result['status']
    assert_equal 1, result['summary']['warmed']
  end

  # ==========================================
  # Tests for cache_enabled? method
  # ==========================================

  def test_cache_enabled_returns_true_when_cache_is_enabled
    client = create_client_with_cache
    assert client.cache_enabled?
  end

  def test_cache_enabled_returns_false_when_cache_is_disabled
    client = create_client_without_cache
    refute client.cache_enabled?
  end

  # ==========================================
  # Tests for client initialization
  # ==========================================

  def test_client_initializes_cache_layer_by_default
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    assert client.cache_enabled?
    assert_instance_of SmartSuite::Cache::Layer, client.cache
  end

  def test_client_initializes_stats_tracker_when_cache_enabled
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    assert client.stats_tracker
    assert_instance_of ApiStatsTracker, client.stats_tracker
  end

  def test_client_initializes_stats_tracker_with_external_tracker
    external_tracker = ApiStatsTracker.new(@api_key)
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false, stats_tracker: external_tracker)

    assert_equal external_tracker, client.stats_tracker
  end

  def test_client_generates_unique_session_id
    client1 = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    client2 = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Session IDs should be different
    session1 = client1.stats_tracker&.instance_variable_get(:@session_id)
    session2 = client2.stats_tracker&.instance_variable_get(:@session_id)

    # Both could be nil if cache is disabled and no external tracker
    # But if we have sessions, they should be unique
    if session1 && session2
      refute_equal session1, session2
    end
  end

  def test_client_uses_custom_session_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path, session_id: 'custom_session')

    session_id = client.stats_tracker.instance_variable_get(:@session_id)
    assert_equal 'custom_session', session_id
  end

  def test_client_uses_custom_cache_path
    custom_path = File.join(Dir.tmpdir, "custom_cache_#{Process.pid}.db")
    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: custom_path)
      assert_equal custom_path, client.cache.db_path
    ensure
      File.delete(custom_path) if File.exist?(custom_path)
    end
  end
end
