# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/query_logger'

class TestQueryLogger < Minitest::Test
  def setup
    # Reset logger before each test - set to nil directly to avoid close issues with mocks
    QueryLogger.instance_variable_set(:@logger, nil)
  end

  def teardown
    # Reset logger after each test - set to nil directly
    QueryLogger.instance_variable_set(:@logger, nil)
  end

  # ========== log_file_path tests ==========

  def test_log_file_path_returns_test_path_in_test_environment
    # We're in test mode, so should use test path
    path = QueryLogger.log_file_path
    assert_includes path, 'smartsuite_mcp_queries_test.log'
  end

  def test_log_file_path_returns_integration_path_when_integration_test
    # Stub integration_test_environment? to return true
    QueryLogger.stub(:integration_test_environment?, true) do
      path = QueryLogger.log_file_path
      assert_includes path, 'smartsuite_mcp_queries_integration.log'
    end
  end

  def test_log_file_path_returns_production_path_when_not_test
    # Stub both methods to return false to simulate production
    QueryLogger.stub(:integration_test_environment?, false) do
      QueryLogger.stub(:test_environment?, false) do
        path = QueryLogger.log_file_path
        assert_includes path, 'smartsuite_mcp_queries.log'
        refute_includes path, '_test'
        refute_includes path, '_integration'
      end
    end
  end

  # ========== reset_logger! tests ==========

  def test_reset_logger_closes_and_clears_logger
    # Create a mock logger with close method
    closed = false
    mock_logger = Object.new
    mock_logger.define_singleton_method(:close) { closed = true }
    QueryLogger.instance_variable_set(:@logger, mock_logger)

    # Reset it
    QueryLogger.reset_logger!

    assert closed, 'Should have called close on logger'
    assert_nil QueryLogger.instance_variable_get(:@logger), 'Logger should be nil after reset'
  end

  def test_reset_logger_handles_nil_logger
    # Ensure logger is nil
    QueryLogger.instance_variable_set(:@logger, nil)

    # Should not raise
    QueryLogger.reset_logger!
    assert_nil QueryLogger.instance_variable_get(:@logger)
  end

  # ========== log_cache_query tests ==========

  def create_mock_logger
    logged_messages = { info: [], error: [], debug: [] }
    mock_logger = Object.new
    mock_logger.define_singleton_method(:info) { |msg| logged_messages[:info] << msg }
    mock_logger.define_singleton_method(:error) { |msg| logged_messages[:error] << msg }
    mock_logger.define_singleton_method(:debug) { |msg| logged_messages[:debug] << msg }
    mock_logger.define_singleton_method(:messages) { logged_messages }
    mock_logger
  end

  def test_log_cache_query_basic
    mock_logger = create_mock_logger
    QueryLogger.instance_variable_set(:@logger, mock_logger)

    QueryLogger.log_cache_query('tbl_123')

    assert_equal 1, mock_logger.messages[:info].size
    assert_includes mock_logger.messages[:info].first, 'CACHE QUERY'
    assert_includes mock_logger.messages[:info].first, 'tbl_123'
  end

  def test_log_cache_query_with_filters
    mock_logger = create_mock_logger
    QueryLogger.instance_variable_set(:@logger, mock_logger)

    QueryLogger.log_cache_query('tbl_456', { 'status' => 'active' })

    assert_equal 1, mock_logger.messages[:info].size
    assert_includes mock_logger.messages[:info].first, 'Filters:'
    assert_includes mock_logger.messages[:info].first, 'status'
  end

  def test_log_cache_query_with_limit_and_offset
    mock_logger = create_mock_logger
    QueryLogger.instance_variable_set(:@logger, mock_logger)

    QueryLogger.log_cache_query('tbl_789', {}, limit: 10, offset: 20)

    assert_equal 1, mock_logger.messages[:info].size
    assert_includes mock_logger.messages[:info].first, 'Limit: 10'
    assert_includes mock_logger.messages[:info].first, 'Offset: 20'
  end

  # ========== format_bytes tests (private method) ==========

  def test_format_bytes_handles_bytes
    result = QueryLogger.send(:format_bytes, 500)
    assert_equal '500B', result
  end

  def test_format_bytes_handles_kilobytes
    result = QueryLogger.send(:format_bytes, 2048)
    assert_equal '2.0KB', result
  end

  def test_format_bytes_handles_megabytes
    result = QueryLogger.send(:format_bytes, 2 * 1024 * 1024)
    assert_equal '2.0MB', result
  end

  def test_format_bytes_handles_nil
    result = QueryLogger.send(:format_bytes, nil)
    assert_nil result
  end

  # ========== truncate_json tests (private method) ==========

  def test_truncate_json_handles_nil
    result = QueryLogger.send(:truncate_json, nil)
    assert_nil result
  end

  def test_truncate_json_handles_short_string
    result = QueryLogger.send(:truncate_json, 'short')
    assert_equal 'short', result
  end

  def test_truncate_json_handles_hash
    result = QueryLogger.send(:truncate_json, { 'key' => 'value' })
    assert_includes result, 'key'
  end

  def test_truncate_json_truncates_long_string
    long_string = 'x' * 300
    result = QueryLogger.send(:truncate_json, long_string, 200)

    assert result.length < long_string.length
    assert_includes result, '... ('
    assert_includes result, 'bytes)'
  end

  # ========== logger initialization tests ==========

  def test_logger_creates_new_instance_when_nil
    QueryLogger.instance_variable_set(:@logger, nil)

    logger = QueryLogger.logger

    assert logger, 'Should create logger instance'
    assert_instance_of Logger, logger
  end

  def test_logger_returns_existing_instance
    QueryLogger.instance_variable_set(:@logger, nil)

    logger1 = QueryLogger.logger
    logger2 = QueryLogger.logger

    assert_same logger1, logger2, 'Should return same logger instance'
  end
end
