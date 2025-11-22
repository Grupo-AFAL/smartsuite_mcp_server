# frozen_string_literal: true

require_relative '../../test_helper'
require 'sqlite3'
require 'fileutils'
require_relative '../../../lib/smartsuite/cache/layer'

class TestCacheMigrations < Minitest::Test
  def setup
    @test_cache_path = File.join(Dir.tmpdir, "test_migrations_#{rand(100_000)}.db")
  end

  def teardown
    FileUtils.rm_f(@test_cache_path) if @test_cache_path && File.exist?(@test_cache_path)
  end

  # Helper to create a raw database with old schema for testing migrations
  def create_legacy_db
    db = SQLite3::Database.new(@test_cache_path)
    db.results_as_hash = true
    db
  end

  # Helper to create a cache layer
  def create_cache
    SmartSuite::Cache::Layer.new(db_path: @test_cache_path)
  end

  # ========== migrate_table_rename_if_needed tests ==========

  def test_migrate_table_rename_old_to_new
    db = create_legacy_db
    # Create old table name
    db.execute <<-SQL
      CREATE TABLE cached_table_schemas (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute("INSERT INTO cached_table_schemas VALUES ('tbl_1', 'sql_tbl_1', 'Table 1', '[]', '{}', datetime('now'), datetime('now'))")
    db.close

    # Initialize cache layer which runs migrations
    cache = create_cache

    # Verify old table is gone, new table exists with data
    old_exists = cache.db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_table_schemas'").first
    new_exists = cache.db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_table_registry'").first

    refute old_exists, 'Old table cached_table_schemas should not exist'
    assert new_exists, 'New table cache_table_registry should exist'

    # Verify data was preserved
    row = cache.db.execute('SELECT * FROM cache_table_registry WHERE table_id = ?', ['tbl_1']).first
    assert_equal 'tbl_1', row['table_id']
    assert_equal 'sql_tbl_1', row['sql_table_name']
  end

  def test_migrate_table_rename_both_exist_drops_old
    db = create_legacy_db
    # Create both old and new tables
    db.execute <<-SQL
      CREATE TABLE cached_table_schemas (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute("INSERT INTO cached_table_schemas VALUES ('old_1', 'sql_old_1', 'Old', '[]', '{}', datetime('now'), datetime('now'))")
    db.execute("INSERT INTO cache_table_registry VALUES ('new_1', 'sql_new_1', 'New', '[]', '{}', datetime('now'), datetime('now'))")
    db.close

    # Initialize cache layer which runs migrations
    cache = create_cache

    # Verify old table is gone
    old_exists = cache.db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cached_table_schemas'").first
    refute old_exists, 'Old table cached_table_schemas should be dropped'

    # Verify new table data is preserved (not overwritten)
    row = cache.db.execute('SELECT * FROM cache_table_registry WHERE table_id = ?', ['new_1']).first
    assert_equal 'new_1', row['table_id']
  end

  def test_migrate_table_rename_no_old_table_noop
    db = create_legacy_db
    # Create only new table
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.close

    # Initialize cache layer - should not error
    cache = create_cache

    # Verify new table still exists
    new_exists = cache.db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cache_table_registry'").first
    assert new_exists
  end

  # ========== migrate_integer_timestamps_to_text tests ==========

  def test_migrate_integer_timestamps_in_cache_table_registry
    db = create_legacy_db
    # Create table with INTEGER timestamps (old format)
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    SQL
    # Insert with Unix timestamp
    now = Time.now.to_i
    db.execute("INSERT INTO cache_table_registry VALUES ('tbl_1', 'sql_tbl_1', 'Table', '[]', '{}', ?, ?)", [now, now])
    db.close

    # Initialize cache layer which runs migrations
    cache = create_cache

    # Verify column types are now TEXT
    cols = cache.db.execute('PRAGMA table_info(cache_table_registry)')
    created_col = cols.find { |c| c['name'] == 'created_at' }
    updated_col = cols.find { |c| c['name'] == 'updated_at' }

    assert_equal 'TEXT', created_col['type']
    assert_equal 'TEXT', updated_col['type']

    # Verify data was converted
    row = cache.db.execute('SELECT created_at, updated_at FROM cache_table_registry WHERE table_id = ?', ['tbl_1']).first
    refute_nil row['created_at']
    # Should be datetime string, not integer
    assert_match(/^\d{4}-\d{2}-\d{2}/, row['created_at'])
  end

  def test_migrate_integer_timestamps_in_cache_ttl_config
    db = create_legacy_db
    # First create cache_table_registry with TEXT (already migrated)
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create cache_ttl_config with INTEGER timestamp
    db.execute <<-SQL
      CREATE TABLE cache_ttl_config (
        table_id TEXT PRIMARY KEY,
        ttl_seconds INTEGER NOT NULL DEFAULT 14400,
        mutation_level TEXT,
        notes TEXT,
        updated_at INTEGER NOT NULL
      )
    SQL
    now = Time.now.to_i
    db.execute("INSERT INTO cache_ttl_config VALUES ('tbl_1', 7200, 'frequent', 'Test', ?)", [now])
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(cache_ttl_config)')
    updated_col = cols.find { |c| c['name'] == 'updated_at' }
    assert_equal 'TEXT', updated_col['type']
  end

  def test_migrate_integer_timestamps_in_api_call_log
    db = create_legacy_db
    # Create required tables first
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create api_call_log with INTEGER timestamp
    db.execute <<-SQL
      CREATE TABLE api_call_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_hash TEXT NOT NULL,
        method TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        solution_id TEXT,
        table_id TEXT,
        timestamp INTEGER NOT NULL,
        session_id TEXT DEFAULT 'legacy'
      )
    SQL
    now = Time.now.to_i
    db.execute("INSERT INTO api_call_log (user_hash, method, endpoint, timestamp) VALUES ('hash123', 'GET', '/test', ?)", [now])
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(api_call_log)')
    ts_col = cols.find { |c| c['name'] == 'timestamp' }
    assert_equal 'TEXT', ts_col['type']
  end

  def test_migrate_integer_timestamps_in_api_stats_summary
    db = create_legacy_db
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute <<-SQL
      CREATE TABLE api_stats_summary (
        user_hash TEXT PRIMARY KEY,
        total_calls INTEGER DEFAULT 0,
        first_call INTEGER,
        last_call INTEGER
      )
    SQL
    now = Time.now.to_i
    db.execute("INSERT INTO api_stats_summary VALUES ('hash123', 10, ?, ?)", [now - 3600, now])
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(api_stats_summary)')
    first_col = cols.find { |c| c['name'] == 'first_call' }
    assert_equal 'TEXT', first_col['type']
  end

  def test_migrate_integer_timestamps_in_cache_stats
    db = create_legacy_db
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute <<-SQL
      CREATE TABLE cache_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        operation TEXT NOT NULL,
        key TEXT,
        timestamp INTEGER NOT NULL,
        metadata TEXT
      )
    SQL
    now = Time.now.to_i
    db.execute("INSERT INTO cache_stats (category, operation, key, timestamp) VALUES ('test', 'read', 'key1', ?)", [now])
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(cache_stats)')
    ts_col = cols.find { |c| c['name'] == 'timestamp' }
    assert_equal 'TEXT', ts_col['type']
  end

  def test_migrate_integer_timestamps_skips_if_already_text
    db = create_legacy_db
    # Create with TEXT timestamps (already migrated)
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute("INSERT INTO cache_table_registry VALUES ('tbl_1', 'sql_tbl_1', 'Table', '[]', '{}', datetime('now'), datetime('now'))")
    db.close

    # Should not error when running migrations
    cache = create_cache

    # Verify data is still intact
    row = cache.db.execute('SELECT * FROM cache_table_registry WHERE table_id = ?', ['tbl_1']).first
    assert_equal 'tbl_1', row['table_id']
  end

  # ========== migrate_cached_tables_schema tests ==========

  def test_migrate_cached_tables_schema_removes_old_adds_new_fields
    db = create_legacy_db
    # Create cache_table_registry first (required)
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create cached_tables with old schema (has description)
    db.execute <<-SQL
      CREATE TABLE cached_tables (
        id TEXT PRIMARY KEY,
        slug TEXT,
        name TEXT,
        solution_id TEXT,
        structure TEXT,
        description TEXT,
        created TEXT,
        created_by TEXT,
        updated TEXT,
        updated_by TEXT,
        deleted_date TEXT,
        deleted_by TEXT,
        record_count INTEGER,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    SQL
    db.execute(<<-SQL)
      INSERT INTO cached_tables (id, slug, name, solution_id, structure, description, created,
        created_by, cached_at, expires_at)
      VALUES ('tbl_1', 'table-1', 'Table 1', 'sol_1', '[]', 'Test desc', datetime('now'),
        'user1', datetime('now'), datetime('now', '+4 hours'))
    SQL
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(cached_tables)')
    col_names = cols.map { |c| c['name'] }

    # Old fields should be removed
    refute_includes col_names, 'description'
    refute_includes col_names, 'updated'
    refute_includes col_names, 'updated_by'
    refute_includes col_names, 'deleted_date'
    refute_includes col_names, 'deleted_by'
    refute_includes col_names, 'record_count'

    # New fields should be added
    assert_includes col_names, 'status'
    assert_includes col_names, 'hidden'
    assert_includes col_names, 'icon'
    assert_includes col_names, 'primary_field'
    assert_includes col_names, 'table_order'
    assert_includes col_names, 'permissions'
    assert_includes col_names, 'field_permissions'
    assert_includes col_names, 'record_term'
    assert_includes col_names, 'fields_count_total'
    assert_includes col_names, 'fields_count_linkedrecordfield'

    # Data should be preserved
    row = cache.db.execute('SELECT * FROM cached_tables WHERE id = ?', ['tbl_1']).first
    assert_equal 'tbl_1', row['id']
    assert_equal 'Table 1', row['name']
  end

  def test_migrate_cached_tables_schema_skips_if_already_migrated
    db = create_legacy_db
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create cached_tables with new schema (no description)
    db.execute <<-SQL
      CREATE TABLE cached_tables (
        id TEXT PRIMARY KEY,
        slug TEXT,
        name TEXT,
        solution_id TEXT,
        structure TEXT,
        created TEXT,
        created_by TEXT,
        status TEXT,
        hidden INTEGER DEFAULT 0,
        icon TEXT,
        primary_field TEXT,
        table_order INTEGER,
        permissions TEXT,
        field_permissions TEXT,
        record_term TEXT,
        fields_count_total INTEGER,
        fields_count_linkedrecordfield INTEGER,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    SQL
    db.execute(<<-SQL)
      INSERT INTO cached_tables (id, name, structure, cached_at, expires_at)
      VALUES ('tbl_1', 'Table', '[]', datetime('now'), datetime('now', '+4 hours'))
    SQL
    db.close

    # Should not error
    cache = create_cache

    # Data should be intact
    row = cache.db.execute('SELECT * FROM cached_tables WHERE id = ?', ['tbl_1']).first
    assert_equal 'tbl_1', row['id']
  end

  # ========== migrate_cached_members_schema tests ==========

  def test_migrate_cached_members_adds_deleted_date_column
    db = create_legacy_db
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create cached_members without deleted_date
    db.execute <<-SQL
      CREATE TABLE cached_members (
        id TEXT PRIMARY KEY,
        email TEXT,
        first_name TEXT,
        last_name TEXT,
        full_name TEXT,
        role TEXT,
        status TEXT,
        job_title TEXT,
        department TEXT,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    SQL
    db.execute(<<-SQL)
      INSERT INTO cached_members (id, email, cached_at, expires_at)
      VALUES ('mem_1', 'test@test.com', datetime('now'), datetime('now', '+4 hours'))
    SQL
    db.close

    cache = create_cache

    cols = cache.db.execute('PRAGMA table_info(cached_members)')
    col_names = cols.map { |c| c['name'] }

    assert_includes col_names, 'deleted_date'

    # Data should be intact
    row = cache.db.execute('SELECT * FROM cached_members WHERE id = ?', ['mem_1']).first
    assert_equal 'mem_1', row['id']
  end

  def test_migrate_cached_members_skips_if_column_exists
    db = create_legacy_db
    db.execute <<-SQL
      CREATE TABLE cache_table_registry (
        table_id TEXT PRIMARY KEY,
        sql_table_name TEXT NOT NULL UNIQUE,
        table_name TEXT,
        structure TEXT NOT NULL,
        field_mapping TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    # Create cached_members with deleted_date already
    db.execute <<-SQL
      CREATE TABLE cached_members (
        id TEXT PRIMARY KEY,
        email TEXT,
        first_name TEXT,
        last_name TEXT,
        full_name TEXT,
        role TEXT,
        status TEXT,
        job_title TEXT,
        department TEXT,
        deleted_date TEXT,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    SQL
    db.execute(<<-SQL)
      INSERT INTO cached_members (id, email, deleted_date, cached_at, expires_at)
      VALUES ('mem_1', 'test@test.com', '2025-01-01', datetime('now'), datetime('now', '+4 hours'))
    SQL
    db.close

    # Should not error
    cache = create_cache

    # Data should be intact including deleted_date
    row = cache.db.execute('SELECT * FROM cached_members WHERE id = ?', ['mem_1']).first
    assert_equal '2025-01-01', row['deleted_date']
  end

  # ========== Idempotency tests ==========

  def test_migrations_are_idempotent
    # Run migrations twice - should not error
    cache1 = create_cache
    cache1.close

    cache2 = create_cache

    # Verify tables exist
    tables = cache2.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r['name'] }
    assert_includes tables, 'cache_table_registry'
  end
end
