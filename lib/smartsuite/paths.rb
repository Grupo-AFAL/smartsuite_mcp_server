# frozen_string_literal: true

require "tmpdir"

module SmartSuite
  # Centralized path management for SmartSuite MCP server.
  #
  # Handles test mode detection and provides consistent paths for:
  # - SQLite cache database
  #
  # In test mode (SMARTSUITE_TEST_MODE=true), uses temporary directory
  # with process-specific filenames to prevent test pollution of production data.
  #
  # @example Get database path
  #   SmartSuite::Paths.database_path
  #   # Production: ~/.smartsuite_mcp_cache.db
  #   # Test mode:  /tmp/smartsuite_test_cache_12345.db
  #
  # Note: Logging paths are managed by SmartSuite::Logger directly.
  module Paths
    module_function

    # Check if running in test mode
    #
    # @return [Boolean] true if SMARTSUITE_TEST_MODE environment variable is 'true'
    def test_mode?
      ENV["SMARTSUITE_TEST_MODE"] == "true"
    end

    # Get the SQLite database path
    #
    # @return [String] path to the cache database file
    def database_path
      if test_mode?
        File.join(Dir.tmpdir, "smartsuite_test_cache_#{Process.pid}.db")
      else
        File.expand_path("~/.smartsuite_mcp_cache.db")
      end
    end
  end
end
