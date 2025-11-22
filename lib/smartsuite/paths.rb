# frozen_string_literal: true

require 'tmpdir'

module SmartSuite
  # Centralized path management for SmartSuite MCP server.
  #
  # Handles test mode detection and provides consistent paths for:
  # - SQLite cache database
  # - Metrics log file
  #
  # In test mode (SMARTSUITE_TEST_MODE=true), uses temporary directory
  # with process-specific filenames to prevent test pollution of production data.
  #
  # @example Get database path
  #   SmartSuite::Paths.database_path
  #   # Production: ~/.smartsuite_mcp_cache.db
  #   # Test mode:  /tmp/smartsuite_test_cache_12345.db
  #
  # @example Get metrics log path
  #   SmartSuite::Paths.metrics_log_path
  #   # Production: ~/.smartsuite_mcp_metrics.log
  #   # Test mode:  /tmp/smartsuite_test_metrics_12345.log
  module Paths
    module_function

    # Check if running in test mode
    #
    # @return [Boolean] true if SMARTSUITE_TEST_MODE environment variable is 'true'
    def test_mode?
      ENV['SMARTSUITE_TEST_MODE'] == 'true'
    end

    # Get the SQLite database path
    #
    # @return [String] path to the cache database file
    def database_path
      if test_mode?
        File.join(Dir.tmpdir, "smartsuite_test_cache_#{Process.pid}.db")
      else
        File.expand_path('~/.smartsuite_mcp_cache.db')
      end
    end

    # Get the metrics log file path
    #
    # @return [String] path to the metrics log file
    def metrics_log_path
      if test_mode?
        File.join(Dir.tmpdir, "smartsuite_test_metrics_#{Process.pid}.log")
      else
        File.expand_path('~/.smartsuite_mcp_metrics.log')
      end
    end
  end
end
