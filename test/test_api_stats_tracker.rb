# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/api_stats_tracker"
require "fileutils"

class TestAPIStatsTracker < Minitest::Test
  def setup
    @test_db_path = File.join(Dir.tmpdir, "test_stats_tracker_#{rand(100_000)}.db")
    @db = SQLite3::Database.new(@test_db_path)
    @db.results_as_hash = true
    # Create tables needed for tracker
    setup_test_tables
  end

  def teardown
    @db&.close
    FileUtils.rm_f(@test_db_path) if @test_db_path
  end

  def setup_test_tables
    @db.execute_batch <<-SQL
      CREATE TABLE IF NOT EXISTS api_call_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_hash TEXT NOT NULL,
        method TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        solution_id TEXT,
        table_id TEXT,
        timestamp TEXT NOT NULL,
        session_id TEXT DEFAULT 'legacy'
      );

      CREATE TABLE IF NOT EXISTS api_stats_summary (
        user_hash TEXT PRIMARY KEY,
        total_calls INTEGER DEFAULT 0,
        first_call TEXT,
        last_call TEXT
      );

      CREATE TABLE IF NOT EXISTS cache_performance (
        table_id TEXT PRIMARY KEY,
        hit_count INTEGER DEFAULT 0,
        miss_count INTEGER DEFAULT 0,
        last_access_time TEXT,
        record_count INTEGER DEFAULT 0,
        cache_size_bytes INTEGER DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    SQL
  end

  # ========== Initialization tests ==========

  def test_initialization_with_shared_db
    tracker = APIStatsTracker.new("test_key", db: @db)

    assert tracker.instance_variable_get(:@db), "Should have database"
    refute tracker.instance_variable_get(:@owns_db), "Should not own shared db"

    tracker.close # Should not close shared db
    # Verify db is still open
    assert @db.execute("SELECT 1"), "Shared db should still be open"
  end

  def test_initialization_with_own_db
    tracker = APIStatsTracker.new("test_key")

    assert tracker.instance_variable_get(:@db), "Should have database"
    assert tracker.instance_variable_get(:@owns_db), "Should own db"

    tracker.close
  end

  def test_initialization_with_custom_session_id
    tracker = APIStatsTracker.new("test_key", db: @db, session_id: "custom_session")

    assert_equal "custom_session", tracker.instance_variable_get(:@session_id)
  end

  # ========== Session ID generation tests ==========

  def test_generate_session_id_format
    tracker = APIStatsTracker.new("test_key", db: @db)
    session_id = tracker.generate_session_id

    # Should match format: YYYYMMDD_HHMMSS_random
    assert_match(/^\d{8}_\d{6}_[a-z0-9]+$/, session_id)
  end

  def test_generate_session_id_uniqueness
    tracker = APIStatsTracker.new("test_key", db: @db)

    ids = 10.times.map { tracker.generate_session_id }

    # All IDs should be unique (very high probability)
    assert_equal 10, ids.uniq.size, "Session IDs should be unique"
  end

  # ========== Tracking tests ==========

  def test_track_api_call_stores_data
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/")

    # Check log was created
    logs = @db.execute("SELECT * FROM api_call_log")
    assert_equal 1, logs.size
    assert_equal "GET", logs[0]["method"]
    assert_includes logs[0]["endpoint"], "solutions"
  end

  def test_track_api_call_extracts_solution_id
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/sol_abc123/")

    logs = @db.execute("SELECT * FROM api_call_log")
    assert_equal "sol_abc123", logs[0]["solution_id"]
  end

  def test_track_api_call_extracts_table_id
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:post, "/api/v1/applications/tbl_xyz789/records/list/")

    logs = @db.execute("SELECT * FROM api_call_log")
    assert_equal "tbl_xyz789", logs[0]["table_id"]
  end

  def test_track_api_call_updates_summary
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/")
    tracker.track_api_call(:post, "/api/v1/solutions/")

    summary = @db.execute("SELECT * FROM api_stats_summary").first
    assert_equal 2, summary["total_calls"]
    refute_nil summary["first_call"]
    refute_nil summary["last_call"]
  end

  # ========== Get stats tests ==========

  def test_get_stats_empty
    tracker = APIStatsTracker.new("test_key", db: @db)

    stats = tracker.get_stats

    assert_equal 0, stats["summary"]["total_calls"]
    assert_nil stats["summary"]["first_call"]
    assert_empty stats["by_method"]
  end

  def test_get_stats_with_data
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/")
    tracker.track_api_call(:post, "/api/v1/applications/tbl_1/records/")
    tracker.track_api_call(:get, "/api/v1/applications/tbl_1/records/")

    stats = tracker.get_stats

    assert_equal 3, stats["summary"]["total_calls"]
    assert_equal 2, stats["by_method"]["GET"]
    assert_equal 1, stats["by_method"]["POST"]
    assert stats["by_table"].key?("tbl_1")
  end

  def test_get_stats_with_session_filter
    tracker = APIStatsTracker.new("test_key", db: @db, session_id: "session_1")

    tracker.track_api_call(:get, "/api/v1/solutions/")

    stats = tracker.get_stats(time_range: "session")

    assert_equal "session", stats["time_range"]
    assert_equal 1, stats["summary"]["total_calls"]
  end

  def test_get_stats_with_7d_filter
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/")

    stats = tracker.get_stats(time_range: "7d")

    assert_equal "7d", stats["time_range"]
    # Recent call should be included
    assert stats["summary"]["total_calls"] >= 1
  end

  def test_get_stats_with_invalid_time_range
    tracker = APIStatsTracker.new("test_key", db: @db)

    stats = tracker.get_stats(time_range: "invalid")

    # Should default to 'all'
    assert_equal "all", stats["time_range"]
  end

  # ========== Reset stats tests ==========

  def test_reset_stats_success
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.track_api_call(:get, "/api/v1/solutions/")
    result = tracker.reset_stats

    assert_equal "success", result["status"]
    assert_includes result["message"], "reset"

    # Verify data was deleted
    logs = @db.execute("SELECT * FROM api_call_log")
    assert_empty logs
  end

  def test_reset_stats_handles_errors
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Drop tables to cause an error
    @db.execute("DROP TABLE api_call_log")

    result = tracker.reset_stats

    assert_equal "error", result["status"]
    assert_includes result["message"], "Failed to reset"
  end

  # ========== Cache stats tests ==========

  def test_get_cache_stats_empty
    tracker = APIStatsTracker.new("test_key", db: @db)

    stats = tracker.get_stats

    # Cache stats should be empty - structured with 'summary' key
    cache_stats = stats["cache_stats"]
    assert_equal 0, cache_stats["summary"]["total_cache_hits"]
    assert_equal 0, cache_stats["summary"]["total_cache_misses"]
    assert_equal 0, cache_stats["summary"]["total_cache_operations"]
    assert_empty cache_stats["by_table"]
  end

  def test_get_cache_stats_with_data
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Insert cache performance data
    @db.execute(
      "INSERT INTO cache_performance (table_id, hit_count, miss_count, record_count, updated_at)
       VALUES (?, ?, ?, ?, ?)",
      [ "tbl_1", 10, 2, 100, Time.now.utc.iso8601 ]
    )
    @db.execute(
      "INSERT INTO cache_performance (table_id, hit_count, miss_count, record_count, updated_at)
       VALUES (?, ?, ?, ?, ?)",
      [ "tbl_2", 5, 1, 50, Time.now.utc.iso8601 ]
    )

    stats = tracker.get_stats
    cache_stats = stats["cache_stats"]

    assert_equal 15, cache_stats["summary"]["total_cache_hits"]
    assert_equal 3, cache_stats["summary"]["total_cache_misses"]
    assert_equal 18, cache_stats["summary"]["total_cache_operations"]
    assert_equal 2, cache_stats["by_table"].size
    # Hit rate should be 15/(15+3) = 83.33%
    assert_in_delta 83.33, cache_stats["summary"]["overall_hit_rate"], 0.01
  end

  # ========== Close tests ==========

  def test_close_closes_owned_db
    tracker = APIStatsTracker.new("test_key")
    tracker.instance_variable_get(:@db)

    tracker.close

    # DB should be closed (we can't easily test this, but at least it shouldn't error)
    # The method should not raise
  end

  def test_close_does_not_close_shared_db
    tracker = APIStatsTracker.new("test_key", db: @db)

    tracker.close

    # Shared DB should still work
    result = @db.execute("SELECT 1")
    assert_equal 1, result.first["1"]
  end

  # ========== Error handling tests ==========

  def test_track_api_call_handles_errors_silently
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Drop the table to cause an error
    @db.execute("DROP TABLE api_call_log")

    # Should not raise - errors are silently caught
    tracker.track_api_call(:get, "/api/v1/solutions/")
  end

  # ========== User hash tests ==========

  def test_user_hash_is_consistent
    tracker1 = APIStatsTracker.new("same_key", db: @db)
    tracker2 = APIStatsTracker.new("same_key", db: @db)

    hash1 = tracker1.instance_variable_get(:@user_hash)
    hash2 = tracker2.instance_variable_get(:@user_hash)

    assert_equal hash1, hash2, "Same API key should produce same hash"
  end

  def test_user_hash_is_different_for_different_keys
    tracker1 = APIStatsTracker.new("key_one", db: @db)
    tracker2 = APIStatsTracker.new("key_two", db: @db)

    hash1 = tracker1.instance_variable_get(:@user_hash)
    hash2 = tracker2.instance_variable_get(:@user_hash)

    refute_equal hash1, hash2, "Different API keys should produce different hashes"
  end

  # ========== Extract ID tests ==========

  def test_extract_solution_id_from_endpoint
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Test various endpoint patterns
    assert_equal "sol_123", tracker.send(:extract_solution_id, "/solutions/sol_123/")
    assert_equal "sol_abc", tracker.send(:extract_solution_id, "/api/v1/solutions/sol_abc/details")
    assert_nil tracker.send(:extract_solution_id, "/api/v1/applications/")
    assert_nil tracker.send(:extract_solution_id, "/api/v1/members/list/")
  end

  def test_extract_table_id_from_endpoint
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Test various endpoint patterns
    assert_equal "tbl_123", tracker.send(:extract_table_id, "/applications/tbl_123/")
    assert_equal "app_xyz", tracker.send(:extract_table_id, "/api/v1/applications/app_xyz/records/")
    assert_nil tracker.send(:extract_table_id, "/api/v1/solutions/")
    assert_nil tracker.send(:extract_table_id, "/api/v1/members/list/")
  end

  # ========== Breakdown tests ==========

  def test_get_breakdown_by_with_multiple_values
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Track multiple calls
    tracker.track_api_call(:get, "/api/v1/solutions/sol_1/")
    tracker.track_api_call(:get, "/api/v1/solutions/sol_1/")
    tracker.track_api_call(:post, "/api/v1/solutions/sol_2/")

    stats = tracker.get_stats

    # Check solution breakdown
    assert_equal 2, stats["by_solution"]["sol_1"]
    assert_equal 1, stats["by_solution"]["sol_2"]
  end

  def test_get_unique_count
    tracker = APIStatsTracker.new("test_key", db: @db)

    # Track calls with different solutions
    tracker.track_api_call(:get, "/api/v1/solutions/sol_1/")
    tracker.track_api_call(:get, "/api/v1/solutions/sol_2/")
    tracker.track_api_call(:get, "/api/v1/solutions/sol_1/")

    stats = tracker.get_stats

    # Should have 2 unique solutions
    assert_equal 2, stats["summary"]["unique_solutions"]
  end
end
