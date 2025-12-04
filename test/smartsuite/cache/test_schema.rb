# frozen_string_literal: true

require_relative "../../test_helper"
require "sqlite3"
require_relative "../../../lib/smartsuite/cache/schema"

# Tests for SmartSuite::Cache::Schema
class TestCacheSchema < Minitest::Test
  def setup
    @db = SQLite3::Database.new(":memory:")
    @db.results_as_hash = true
  end

  def teardown
    @db.close
  end

  # ==============================================================================
  # api_stats_tables_sql tests
  # ==============================================================================

  def test_api_stats_tables_sql_creates_api_call_log
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='api_call_log'")
    assert_equal 1, tables.size
  end

  def test_api_stats_tables_sql_creates_api_stats_summary
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='api_stats_summary'")
    assert_equal 1, tables.size
  end

  def test_api_stats_tables_sql_creates_cache_performance
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_performance'")
    assert_equal 1, tables.size
  end

  def test_api_stats_tables_sql_creates_indexes
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)

    indexes = @db.execute("SELECT name FROM sqlite_master WHERE type='index'")
    index_names = indexes.map { |i| i["name"] }

    assert_includes index_names, "idx_api_call_log_user"
    assert_includes index_names, "idx_api_call_log_session"
    assert_includes index_names, "idx_api_call_log_timestamp"
  end

  def test_api_stats_tables_sql_is_idempotent
    # Execute twice - should not raise
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='api_call_log'")
    assert_equal 1, tables.size
  end

  # ==============================================================================
  # cache_registry_tables_sql tests
  # ==============================================================================

  def test_cache_registry_tables_sql_creates_cache_table_registry
    @db.execute_batch(SmartSuite::Cache::Schema.cache_registry_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_table_registry'")
    assert_equal 1, tables.size
  end

  def test_cache_registry_tables_sql_creates_cache_ttl_config
    @db.execute_batch(SmartSuite::Cache::Schema.cache_registry_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_ttl_config'")
    assert_equal 1, tables.size
  end

  def test_cache_registry_tables_sql_creates_cache_stats
    @db.execute_batch(SmartSuite::Cache::Schema.cache_registry_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_stats'")
    assert_equal 1, tables.size
  end

  def test_cache_registry_tables_sql_uses_custom_ttl
    custom_ttl = 7200
    sql = SmartSuite::Cache::Schema.cache_registry_tables_sql(default_ttl: custom_ttl)

    assert_includes sql, custom_ttl.to_s
  end

  def test_cache_registry_tables_sql_uses_default_ttl
    sql = SmartSuite::Cache::Schema.cache_registry_tables_sql

    assert_includes sql, SmartSuite::Cache::Schema::DEFAULT_TTL.to_s
  end

  # ==============================================================================
  # cached_data_tables_sql tests
  # ==============================================================================

  def test_cached_data_tables_sql_creates_cached_solutions
    @db.execute_batch(SmartSuite::Cache::Schema.cached_data_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_solutions'")
    assert_equal 1, tables.size
  end

  def test_cached_data_tables_sql_creates_cached_tables
    @db.execute_batch(SmartSuite::Cache::Schema.cached_data_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_tables'")
    assert_equal 1, tables.size
  end

  def test_cached_data_tables_sql_creates_cached_members
    @db.execute_batch(SmartSuite::Cache::Schema.cached_data_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_members'")
    assert_equal 1, tables.size
  end

  def test_cached_data_tables_sql_creates_cached_teams
    @db.execute_batch(SmartSuite::Cache::Schema.cached_data_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_teams'")
    assert_equal 1, tables.size
  end

  def test_cached_data_tables_sql_creates_indexes
    @db.execute_batch(SmartSuite::Cache::Schema.cached_data_tables_sql)

    indexes = @db.execute("SELECT name FROM sqlite_master WHERE type='index'")
    index_names = indexes.map { |i| i["name"] }

    assert_includes index_names, "idx_cached_tables_solution"
    assert_includes index_names, "idx_cached_tables_expires"
    assert_includes index_names, "idx_cached_solutions_expires"
    assert_includes index_names, "idx_cached_members_expires"
    assert_includes index_names, "idx_cached_teams_expires"
  end

  # ==============================================================================
  # all_metadata_tables_sql tests
  # ==============================================================================

  def test_all_metadata_tables_sql_creates_all_tables
    @db.execute_batch(SmartSuite::Cache::Schema.all_metadata_tables_sql)

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |t| t["name"] }

    # API stats tables
    assert_includes table_names, "api_call_log"
    assert_includes table_names, "api_stats_summary"
    assert_includes table_names, "cache_performance"

    # Cache registry tables
    assert_includes table_names, "cache_table_registry"
    assert_includes table_names, "cache_ttl_config"
    assert_includes table_names, "cache_stats"

    # Cached data tables
    assert_includes table_names, "cached_solutions"
    assert_includes table_names, "cached_tables"
    assert_includes table_names, "cached_members"
    assert_includes table_names, "cached_teams"
  end

  def test_all_metadata_tables_sql_accepts_custom_ttl
    custom_ttl = 3600
    sql = SmartSuite::Cache::Schema.all_metadata_tables_sql(default_ttl: custom_ttl)

    assert_includes sql, custom_ttl.to_s
  end

  # ==============================================================================
  # Constants tests
  # ==============================================================================

  def test_default_ttl_constant
    # 4 hours in seconds
    assert_equal 14_400, SmartSuite::Cache::Schema::DEFAULT_TTL
  end
end
