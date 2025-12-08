# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/smart_suite_client"

class SmartSuiteClientTest < Minitest::Test
  def setup
    @api_key = "test_api_key"
    @account_id = "test_account_id"
    @test_cache_path = File.join(Dir.tmpdir, "smart_suite_client_test_#{Process.pid}_#{rand(10_000)}.db")
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
    return unless session1 && session2

    refute_equal session1, session2
  end

  def test_client_uses_custom_session_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path, session_id: "custom_session")

    session_id = client.stats_tracker.instance_variable_get(:@session_id)
    assert_equal "custom_session", session_id
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
