# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/smart_suite/paths"

class TestPaths < Minitest::Test
  def test_test_mode_returns_true_when_env_set
    # test_helper.rb sets SMARTSUITE_TEST_MODE=true
    assert SmartSuite::Paths.test_mode?
  end

  def test_test_mode_returns_false_when_env_not_set
    original = ENV.fetch("SMARTSUITE_TEST_MODE", nil)
    ENV["SMARTSUITE_TEST_MODE"] = nil

    refute SmartSuite::Paths.test_mode?
  ensure
    ENV["SMARTSUITE_TEST_MODE"] = original
  end

  def test_database_path_in_test_mode
    path = SmartSuite::Paths.database_path

    assert path.include?(Dir.tmpdir), "Test mode should use tmpdir"
    assert path.include?("smartsuite_test_cache_"), "Test mode should use test prefix"
    assert path.include?(Process.pid.to_s), "Test mode should include process ID"
    assert path.end_with?(".db"), "Should end with .db extension"
  end

  def test_database_path_in_production_mode
    original = ENV.fetch("SMARTSUITE_TEST_MODE", nil)
    ENV["SMARTSUITE_TEST_MODE"] = nil

    path = SmartSuite::Paths.database_path

    assert path.include?(Dir.home), "Production mode should use home directory"
    assert path.include?(".smartsuite_mcp_cache.db"), "Production mode should use standard filename"
  ensure
    ENV["SMARTSUITE_TEST_MODE"] = original
  end

  def test_paths_are_consistent_across_calls
    # Multiple calls should return the same paths (same PID, same tmpdir)
    db_path1 = SmartSuite::Paths.database_path
    db_path2 = SmartSuite::Paths.database_path

    assert_equal db_path1, db_path2, "Database path should be consistent"
  end
end
