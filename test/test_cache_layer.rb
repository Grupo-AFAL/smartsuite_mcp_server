# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite/cache/layer'
require 'sqlite3'
require 'fileutils'
require 'time'

class TestCacheLayer < Minitest::Test
  def setup
    # Create a temporary database for testing
    @test_db_path = File.join(Dir.tmpdir, "test_cache_layer_#{rand(100_000)}.db")
    @cache = SmartSuite::Cache::Layer.new(db_path: @test_db_path)
  end

  def teardown
    @cache.close
    FileUtils.rm_f(@test_db_path) if File.exist?(@test_db_path)
  end

  # Test cache initialization
  def test_initialize_creates_database
    assert File.exist?(@test_db_path), 'Database file should be created'
  end

  def test_initialize_sets_file_permissions
    permissions = File.stat(@test_db_path).mode & 0o777
    assert_equal 0o600, permissions, 'File should have 600 permissions'
  end

  def test_initialize_creates_metadata_tables
    tables = @cache.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r['name'] }

    assert_includes tables, 'cache_table_registry'
    assert_includes tables, 'cache_ttl_config'
    assert_includes tables, 'cache_stats'
    assert_includes tables, 'cache_performance'
    assert_includes tables, 'cached_solutions'
    assert_includes tables, 'cached_tables'
  end

  # Test cache_table_records
  def test_cache_table_records
    table_id = 'tbl_test_123'
    structure = create_test_structure
    records = create_test_records

    count = @cache.cache_table_records(table_id, structure, records)

    assert_equal 3, count, 'Should return number of records cached'
  end

  def test_cache_table_records_with_custom_ttl
    table_id = 'tbl_test_456'
    structure = create_test_structure
    records = create_test_records
    custom_ttl = 7200 # 2 hours

    @cache.cache_table_records(table_id, structure, records, ttl: custom_ttl)

    # Verify records were cached with correct TTL
    schema = @cache.send(:get_cached_table_schema, table_id)
    sql_table_name = schema['sql_table_name']

    result = @cache.db.execute("SELECT expires_at FROM #{sql_table_name} LIMIT 1").first
    expires_at = Time.parse(result['expires_at'])
    expected_expires = Time.now + custom_ttl

    # Allow 10 second tolerance for test execution time
    assert_in_delta expected_expires.to_i, expires_at.to_i, 10
  end

  def test_cache_table_records_replaces_existing
    table_id = 'tbl_test_789'
    structure = create_test_structure
    records = create_test_records

    # Cache first batch
    @cache.cache_table_records(table_id, structure, records)

    # Cache second batch (should replace)
    new_records = [
      { 'id' => 'rec_new1', 'name' => 'New Record 1', 'status' => 'active' },
      { 'id' => 'rec_new2', 'name' => 'New Record 2', 'status' => 'pending' }
    ]
    count = @cache.cache_table_records(table_id, structure, new_records)

    assert_equal 2, count

    # Verify only new records exist
    query_results = @cache.query(table_id).execute
    assert_equal 2, query_results.size
    assert(query_results.all? { |r| r['id'].start_with?('rec_new') })
  end

  # Test cache validity
  def test_cache_valid_with_valid_cache
    table_id = 'tbl_valid'
    structure = create_test_structure
    records = create_test_records

    @cache.cache_table_records(table_id, structure, records)

    assert @cache.cache_valid?(table_id), 'Cache should be valid immediately after caching'
  end

  def test_cache_valid_with_expired_cache
    table_id = 'tbl_expired'
    structure = create_test_structure
    records = create_test_records

    # Cache with very short TTL
    @cache.cache_table_records(table_id, structure, records, ttl: -1) # Expired immediately

    refute @cache.cache_valid?(table_id), 'Cache should be invalid when expired'
  end

  def test_cache_valid_with_no_cache
    refute @cache.cache_valid?('tbl_nonexistent'), 'Cache should be invalid for uncached table'
  end

  # Test invalidate_table_cache
  def test_invalidate_table_cache
    table_id = 'tbl_invalidate'
    structure = create_test_structure
    records = create_test_records

    @cache.cache_table_records(table_id, structure, records)
    assert @cache.cache_valid?(table_id), 'Cache should be valid before invalidation'

    @cache.send(:invalidate_table_cache, table_id)

    refute @cache.cache_valid?(table_id), 'Cache should be invalid after invalidation'
  end

  # Test solution caching
  def test_cache_solutions
    solutions = create_test_solutions

    count = @cache.cache_solutions(solutions)

    assert_equal 3, count, 'Should return number of solutions cached'
  end

  def test_get_cached_solutions
    solutions = create_test_solutions
    @cache.cache_solutions(solutions)

    cached = @cache.get_cached_solutions

    assert cached.is_a?(Array), 'Should return array'
    assert_equal 3, cached.size
    assert_equal 'sol_1', cached[0]['id']
    assert_equal 'Solution 1', cached[0]['name']
  end

  def test_get_cached_solutions_when_expired
    solutions = create_test_solutions
    @cache.cache_solutions(solutions, ttl: -1) # Expired

    cached = @cache.get_cached_solutions

    assert_nil cached, 'Should return nil when cache expired'
  end

  def test_solutions_cache_valid
    solutions = create_test_solutions
    @cache.cache_solutions(solutions)

    assert @cache.send(:solutions_cache_valid?), 'Solutions cache should be valid'
  end

  def test_invalidate_solutions_cache
    solutions = create_test_solutions
    @cache.cache_solutions(solutions)

    @cache.send(:invalidate_solutions_cache)

    refute @cache.send(:solutions_cache_valid?), 'Solutions cache should be invalid after invalidation'
  end

  # Test table list caching
  def test_cache_table_list
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)

    count = @cache.cache_table_list(solution_id, tables)

    assert_equal 2, count, 'Should return number of tables cached'
  end

  def test_cache_table_list_all_tables
    tables = create_test_tables(nil) # All tables

    count = @cache.cache_table_list(nil, tables)

    assert_equal 2, count
  end

  def test_get_cached_table_list
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables)

    cached = @cache.get_cached_table_list(solution_id)

    assert cached.is_a?(Array), 'Should return array'
    assert_equal 2, cached.size
    assert_equal 'tbl_1', cached[0]['id']
  end

  def test_get_cached_table_list_when_expired
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables, ttl: -1) # Expired

    cached = @cache.get_cached_table_list(solution_id)

    assert_nil cached, 'Should return nil when cache expired'
  end

  def test_table_list_cache_valid
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables)

    assert @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be valid'
  end

  def test_invalidate_table_list_cache
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables)

    @cache.send(:invalidate_table_list_cache, solution_id)

    refute @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be invalid'
  end

  # Test refresh_cache
  def test_refresh_cache_solutions
    solutions = create_test_solutions
    @cache.cache_solutions(solutions)

    result = @cache.refresh_cache('solutions')

    assert_equal 'refresh', result['operation']
    assert_includes result['message'], 'solutions'
    refute @cache.send(:solutions_cache_valid?)
  end

  def test_refresh_cache_tables
    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables)

    result = @cache.refresh_cache('tables', solution_id: solution_id)

    assert_equal 'refresh', result['operation']
    assert_includes result['message'], solution_id
    refute @cache.send(:table_list_cache_valid?, solution_id)
  end

  def test_refresh_cache_records
    table_id = 'tbl_123'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    result = @cache.refresh_cache('records', table_id: table_id)

    assert_equal 'refresh', result['operation']
    assert_includes result['message'], table_id
    refute @cache.cache_valid?(table_id)
  end

  def test_refresh_cache_records_requires_table_id
    error = assert_raises(ArgumentError) do
      @cache.refresh_cache('records')
    end

    assert_includes error.message, 'table_id is required'
  end

  def test_refresh_cache_invalid_resource
    error = assert_raises(ArgumentError) do
      @cache.refresh_cache('invalid')
    end

    assert_includes error.message, 'Unknown resource type'
  end

  # Test get_tables_to_warm
  def test_get_tables_to_warm_with_array
    tables = %w[tbl_1 tbl_2 tbl_3]

    result = @cache.get_tables_to_warm(tables: tables)

    assert_equal tables, result
  end

  def test_get_tables_to_warm_with_string
    table = 'tbl_123'

    result = @cache.get_tables_to_warm(tables: table)

    assert_equal [table], result
  end

  def test_get_tables_to_warm_auto_mode
    # Insert some performance data
    @cache.db.execute(
      "INSERT INTO cache_performance (table_id, hit_count, miss_count, updated_at)
       VALUES ('tbl_popular', 100, 10, ?)",
      [Time.now.utc.iso8601]
    )
    @cache.db.execute(
      "INSERT INTO cache_performance (table_id, hit_count, miss_count, updated_at)
       VALUES ('tbl_less_popular', 10, 1, ?)",
      [Time.now.utc.iso8601]
    )

    result = @cache.get_tables_to_warm(tables: 'auto', count: 2)

    assert_equal 2, result.size
    assert_equal 'tbl_popular', result[0], 'Should return most accessed table first'
  end

  def test_get_tables_to_warm_nil_returns_auto
    result = @cache.get_tables_to_warm(tables: nil, count: 5)

    assert result.is_a?(Array), 'Should return empty array when no performance data'
  end

  # Test get_cache_status
  def test_get_cache_status
    # Cache some data
    solutions = create_test_solutions
    @cache.cache_solutions(solutions)

    solution_id = 'sol_123'
    tables = create_test_tables(solution_id)
    @cache.cache_table_list(solution_id, tables)

    table_id = 'tbl_123'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    status = @cache.get_cache_status

    assert status.is_a?(Hash), 'Should return hash'
    assert status.key?('timestamp')
    assert status.key?('solutions')
    assert status.key?('tables')
    assert status.key?('records')

    # Verify solutions status
    assert_equal 3, status['solutions']['count']
    assert status['solutions']['is_valid']

    # Verify tables status
    assert_equal 2, status['tables']['count']
    assert status['tables']['is_valid']

    # Verify records status
    assert status['records'].is_a?(Array)
    assert_equal 1, status['records'].size
    assert_equal table_id, status['records'][0]['table_id']
  end

  def test_get_cache_status_specific_table
    table_id = 'tbl_specific'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    status = @cache.get_cache_status(table_id: table_id)

    assert_equal 1, status['records'].size
    assert_equal table_id, status['records'][0]['table_id']
  end

  # Test extract_field_value for different field types
  def test_extract_field_value_text_field
    field_info = { 'slug' => 'name', 'field_type' => 'textfield', 'label' => 'Name' }
    value = 'Test Name'

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal({ 'name' => 'Test Name' }, result)
  end

  def test_extract_field_value_number_field
    field_info = { 'slug' => 'amount', 'field_type' => 'numberfield', 'label' => 'Amount' }
    value = 123.45

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal({ 'amount' => 123.45 }, result)
  end

  def test_extract_field_value_yesno_field
    field_info = { 'slug' => 'active', 'field_type' => 'yesnofield', 'label' => 'Active' }

    result_true = @cache.send(:extract_field_value, field_info, true)
    result_false = @cache.send(:extract_field_value, field_info, false)

    assert_equal({ 'active' => 1 }, result_true)
    assert_equal({ 'active' => 0 }, result_false)
  end

  def test_extract_field_value_firstcreated_field
    field_info = { 'slug' => 's123', 'field_type' => 'firstcreatedfield', 'label' => 'Created' }
    value = { 'on' => '2025-01-15T10:00:00Z', 'by' => 'user_123' }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-15T10:00:00Z', result['created_on']
    assert_equal 'user_123', result['created_by']
  end

  def test_extract_field_value_status_field
    field_info = { 'slug' => 'status', 'field_type' => 'statusfield', 'label' => 'Status' }
    value = { 'value' => 'Active', 'updated_on' => '2025-01-15T10:00:00Z' }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 'Active', result['status']
    assert_equal '2025-01-15T10:00:00Z', result['status_updated_on']
  end

  def test_extract_field_value_array_field
    field_info = { 'slug' => 'tags', 'field_type' => 'multipleselectfield', 'label' => 'Tags' }
    value = %w[tag1 tag2 tag3]

    result = @cache.send(:extract_field_value, field_info, value)

    assert result['tags'].is_a?(String), 'Arrays should be converted to JSON'
    assert_equal %w[tag1 tag2 tag3], JSON.parse(result['tags'])
  end

  def test_extract_field_value_nil_returns_empty
    field_info = { 'slug' => 'name', 'field_type' => 'textfield', 'label' => 'Name' }

    result = @cache.send(:extract_field_value, field_info, nil)

    assert_equal({}, result)
  end

  # Test parse_timestamp
  def test_parse_timestamp_valid
    timestamp = '2025-01-15T10:30:00Z'

    result = @cache.send(:parse_timestamp, timestamp)

    assert_equal timestamp, result
  end

  def test_parse_timestamp_nil
    result = @cache.send(:parse_timestamp, nil)

    assert_nil result
  end

  def test_parse_timestamp_invalid
    result = @cache.send(:parse_timestamp, 'invalid-timestamp')

    assert_nil result, 'Invalid timestamps should return nil'
  end

  # Test query method
  def test_query_returns_query_builder
    table_id = 'tbl_123'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    query = @cache.query(table_id)

    assert query.is_a?(SmartSuite::Cache::Query), 'Should return Query instance'
  end

  # Test close method
  def test_close_closes_database
    @cache.close

    error = assert_raises(ArgumentError) do
      @cache.db.execute('SELECT 1')
    end

    assert_includes error.message.downcase, 'closed', 'Database should be closed'
  end

  # ========== Performance Module Tests ==========

  def test_track_cache_hit
    table_id = 'tbl_perf_hit'

    @cache.track_cache_hit(table_id)

    # Access internal counters to verify
    counters = @cache.instance_variable_get(:@perf_counters)
    assert_equal 1, counters[table_id][:hits]
    assert_equal 0, counters[table_id][:misses]
  end

  def test_track_cache_miss
    table_id = 'tbl_perf_miss'

    @cache.track_cache_miss(table_id)

    counters = @cache.instance_variable_get(:@perf_counters)
    assert_equal 0, counters[table_id][:hits]
    assert_equal 1, counters[table_id][:misses]
  end

  def test_track_cache_hit_increments_operations_counter
    table_id = 'tbl_perf_ops'

    initial_ops = @cache.instance_variable_get(:@perf_operations_since_flush)
    @cache.track_cache_hit(table_id)
    final_ops = @cache.instance_variable_get(:@perf_operations_since_flush)

    assert_equal initial_ops + 1, final_ops
  end

  def test_track_cache_miss_increments_operations_counter
    table_id = 'tbl_perf_ops'

    initial_ops = @cache.instance_variable_get(:@perf_operations_since_flush)
    @cache.track_cache_miss(table_id)
    final_ops = @cache.instance_variable_get(:@perf_operations_since_flush)

    assert_equal initial_ops + 1, final_ops
  end

  def test_flush_performance_counters
    table_id = 'tbl_perf_flush'

    # Track some hits and misses
    3.times { @cache.track_cache_hit(table_id) }
    2.times { @cache.track_cache_miss(table_id) }

    # Force flush
    @cache.flush_performance_counters

    # Verify counters were cleared
    counters = @cache.instance_variable_get(:@perf_counters)
    assert counters.empty?, 'Counters should be cleared after flush'

    # Verify data was written to database
    result = @cache.db.execute(
      'SELECT hit_count, miss_count FROM cache_performance WHERE table_id = ?',
      [table_id]
    ).first

    assert_equal 3, result['hit_count']
    assert_equal 2, result['miss_count']
  end

  def test_flush_performance_counters_accumulates
    table_id = 'tbl_perf_accum'

    # First batch
    2.times { @cache.track_cache_hit(table_id) }
    @cache.flush_performance_counters

    # Second batch
    3.times { @cache.track_cache_hit(table_id) }
    1.times { @cache.track_cache_miss(table_id) }
    @cache.flush_performance_counters

    # Verify accumulated values
    result = @cache.db.execute(
      'SELECT hit_count, miss_count FROM cache_performance WHERE table_id = ?',
      [table_id]
    ).first

    assert_equal 5, result['hit_count'], 'Hits should accumulate: 2 + 3 = 5'
    assert_equal 1, result['miss_count']
  end

  def test_flush_performance_counters_empty_does_nothing
    # Ensure counters are empty
    @cache.instance_variable_set(:@perf_counters, Hash.new { |h, k| h[k] = { hits: 0, misses: 0 } })

    # This should not raise
    @cache.flush_performance_counters

    # Verify no records were inserted
    result = @cache.db.execute('SELECT COUNT(*) as cnt FROM cache_performance').first
    assert_equal 0, result['cnt']
  end

  def test_flush_performance_counters_if_needed_under_threshold
    table_id = 'tbl_perf_threshold'

    # Track fewer than 100 operations
    10.times { @cache.track_cache_hit(table_id) }

    # Reset flush time to recent
    @cache.instance_variable_set(:@perf_last_flush, Time.now.utc)

    # Counters should still exist (not flushed)
    counters = @cache.instance_variable_get(:@perf_counters)
    refute counters.empty?, 'Counters should not be flushed under threshold'
  end

  def test_flush_performance_counters_if_needed_over_operations_threshold
    table_id = 'tbl_perf_ops_threshold'

    # Set operations to 99
    @cache.instance_variable_set(:@perf_operations_since_flush, 99)
    @cache.instance_variable_set(:@perf_last_flush, Time.now.utc)

    # This should trigger flush (100th operation)
    @cache.track_cache_hit(table_id)

    # Verify database was updated
    result = @cache.db.execute(
      'SELECT hit_count FROM cache_performance WHERE table_id = ?',
      [table_id]
    ).first

    assert result, 'Performance data should be flushed to database'
  end

  def test_flush_performance_counters_if_needed_over_time_threshold
    table_id = 'tbl_perf_time_threshold'

    # Track some data
    @cache.track_cache_hit(table_id)

    # Set last flush to more than 5 minutes ago
    @cache.instance_variable_set(:@perf_last_flush, Time.now.utc - 400)
    @cache.instance_variable_set(:@perf_operations_since_flush, 1)

    # This should trigger flush due to time threshold
    @cache.flush_performance_counters_if_needed

    # Verify counters were cleared
    counters = @cache.instance_variable_get(:@perf_counters)
    assert counters.empty?, 'Counters should be flushed after time threshold'
  end

  def test_get_cache_performance_empty
    result = @cache.get_cache_performance

    assert result.is_a?(Array)
    assert result.empty?, 'Should return empty array when no performance data'
  end

  def test_get_cache_performance_with_data
    table_id = 'tbl_perf_get'

    # Track some data and flush
    5.times { @cache.track_cache_hit(table_id) }
    3.times { @cache.track_cache_miss(table_id) }
    @cache.flush_performance_counters

    result = @cache.get_cache_performance

    assert_equal 1, result.size
    perf = result.first

    assert_equal table_id, perf['table_id']
    assert_equal 5, perf['hit_count']
    assert_equal 3, perf['miss_count']
    assert_equal 8, perf['total_operations']
    assert_in_delta 62.5, perf['hit_rate'], 0.01 # 5/8 = 62.5%
  end

  def test_get_cache_performance_filter_by_table_id
    # Track data for multiple tables
    3.times { @cache.track_cache_hit('tbl_perf_a') }
    2.times { @cache.track_cache_hit('tbl_perf_b') }
    @cache.flush_performance_counters

    result = @cache.get_cache_performance(table_id: 'tbl_perf_a')

    assert_equal 1, result.size
    assert_equal 'tbl_perf_a', result.first['table_id']
  end

  def test_get_cache_performance_hit_rate_zero_operations
    # Insert a record with zero operations directly
    @cache.db.execute(
      "INSERT INTO cache_performance (table_id, hit_count, miss_count, updated_at)
       VALUES ('tbl_perf_zero', 0, 0, ?)",
      [Time.now.utc.iso8601]
    )

    result = @cache.get_cache_performance(table_id: 'tbl_perf_zero')

    assert_equal 0.0, result.first['hit_rate'], 'Hit rate should be 0 when no operations'
  end

  def test_get_cache_performance_flushes_pending_counters
    table_id = 'tbl_perf_pending'

    # Track data but don't flush
    5.times { @cache.track_cache_hit(table_id) }

    # get_cache_performance should flush first
    result = @cache.get_cache_performance(table_id: table_id)

    assert_equal 1, result.size
    assert_equal 5, result.first['hit_count']
  end

  # Test cascading cache invalidation
  def test_invalidate_table_list_cache_cascades_to_records
    solution_id = 'sol_cascade_test'

    # Cache tables for the solution
    tables = [
      { 'id' => 'tbl_cascade_1', 'name' => 'Table 1', 'solution_id' => solution_id },
      { 'id' => 'tbl_cascade_2', 'name' => 'Table 2', 'solution_id' => solution_id }
    ]
    @cache.cache_table_list(solution_id, tables)

    # Cache records for each table
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records('tbl_cascade_1', structure, records)
    @cache.cache_table_records('tbl_cascade_2', structure, records)

    # Verify caches are valid
    assert @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be valid'
    assert @cache.cache_valid?('tbl_cascade_1'), 'Table 1 records cache should be valid'
    assert @cache.cache_valid?('tbl_cascade_2'), 'Table 2 records cache should be valid'

    # Invalidate table list for solution (should cascade to records)
    @cache.send(:invalidate_table_list_cache, solution_id)

    # Verify all caches are invalidated
    refute @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be invalid'
    refute @cache.cache_valid?('tbl_cascade_1'), 'Table 1 records cache should be invalid'
    refute @cache.cache_valid?('tbl_cascade_2'), 'Table 2 records cache should be invalid'
  end

  def test_invalidate_solutions_cache_cascades_to_tables_and_records
    solution_id = 'sol_cascade_all'

    # Cache solutions
    solutions = [
      { 'id' => solution_id, 'name' => 'Solution Cascade', 'logo_icon' => 'icon', 'logo_color' => '#000000' }
    ]
    @cache.cache_solutions(solutions)

    # Cache tables for the solution
    tables = [
      { 'id' => 'tbl_sol_cascade_1', 'name' => 'Table 1', 'solution_id' => solution_id },
      { 'id' => 'tbl_sol_cascade_2', 'name' => 'Table 2', 'solution_id' => solution_id }
    ]
    @cache.cache_table_list(solution_id, tables)

    # Cache records for each table
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records('tbl_sol_cascade_1', structure, records)
    @cache.cache_table_records('tbl_sol_cascade_2', structure, records)

    # Verify all caches are valid
    assert @cache.send(:solutions_cache_valid?), 'Solutions cache should be valid'
    assert @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be valid'
    assert @cache.cache_valid?('tbl_sol_cascade_1'), 'Table 1 records cache should be valid'
    assert @cache.cache_valid?('tbl_sol_cascade_2'), 'Table 2 records cache should be valid'

    # Invalidate solutions (should cascade to tables and records)
    @cache.send(:invalidate_solutions_cache)

    # Verify all caches are invalidated
    refute @cache.send(:solutions_cache_valid?), 'Solutions cache should be invalid'
    refute @cache.send(:table_list_cache_valid?, solution_id), 'Table list cache should be invalid'
    refute @cache.cache_valid?('tbl_sol_cascade_1'), 'Table 1 records cache should be invalid'
    refute @cache.cache_valid?('tbl_sol_cascade_2'), 'Table 2 records cache should be invalid'
  end

  def test_refresh_cache_tables_cascades_to_records
    solution_id = 'sol_refresh_cascade'

    # Cache tables
    tables = [
      { 'id' => 'tbl_refresh_1', 'name' => 'Table 1', 'solution_id' => solution_id }
    ]
    @cache.cache_table_list(solution_id, tables)

    # Cache records
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records('tbl_refresh_1', structure, records)

    # Verify caches are valid
    assert @cache.send(:table_list_cache_valid?, solution_id), 'Table list should be valid'
    assert @cache.cache_valid?('tbl_refresh_1'), 'Records should be valid'

    # Refresh table list (should cascade to records)
    @cache.refresh_cache('tables', solution_id: solution_id)

    # Verify both caches are invalidated
    refute @cache.send(:table_list_cache_valid?, solution_id), 'Table list should be invalid after refresh'
    refute @cache.cache_valid?('tbl_refresh_1'), 'Records should be invalid after refresh'
  end

  def test_refresh_cache_solutions_cascades_to_all
    solution_id = 'sol_refresh_all'

    # Cache everything
    solutions = [{ 'id' => solution_id, 'name' => 'Solution', 'logo_icon' => 'icon', 'logo_color' => '#000' }]
    @cache.cache_solutions(solutions)

    tables = [{ 'id' => 'tbl_refresh_all', 'name' => 'Table', 'solution_id' => solution_id }]
    @cache.cache_table_list(solution_id, tables)

    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records('tbl_refresh_all', structure, records)

    # Verify all valid
    assert @cache.send(:solutions_cache_valid?), 'Solutions should be valid'
    assert @cache.send(:table_list_cache_valid?, solution_id), 'Tables should be valid'
    assert @cache.cache_valid?('tbl_refresh_all'), 'Records should be valid'

    # Refresh solutions (should cascade to everything)
    @cache.refresh_cache('solutions')

    # Verify all invalid
    refute @cache.send(:solutions_cache_valid?), 'Solutions should be invalid'
    refute @cache.send(:table_list_cache_valid?, solution_id), 'Tables should be invalid'
    refute @cache.cache_valid?('tbl_refresh_all'), 'Records should be invalid'
  end

  private

  def create_test_structure
    {
      'name' => 'Test Table',
      'structure' => [
        { 'slug' => 'name', 'label' => 'Name', 'field_type' => 'textfield' },
        { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield' },
        { 'slug' => 'priority', 'label' => 'Priority', 'field_type' => 'numberfield' }
      ]
    }
  end

  def create_test_records
    [
      { 'id' => 'rec_1', 'name' => 'Record 1', 'status' => { 'value' => 'active' }, 'priority' => 1 },
      { 'id' => 'rec_2', 'name' => 'Record 2', 'status' => { 'value' => 'pending' }, 'priority' => 2 },
      { 'id' => 'rec_3', 'name' => 'Record 3', 'status' => { 'value' => 'active' }, 'priority' => 3 }
    ]
  end

  def create_test_solutions
    [
      { 'id' => 'sol_1', 'name' => 'Solution 1', 'logo_icon' => 'icon1', 'logo_color' => '#FF0000' },
      { 'id' => 'sol_2', 'name' => 'Solution 2', 'logo_icon' => 'icon2', 'logo_color' => '#00FF00' },
      { 'id' => 'sol_3', 'name' => 'Solution 3', 'logo_icon' => 'icon3', 'logo_color' => '#0000FF' }
    ]
  end

  def create_test_tables(solution_id)
    [
      { 'id' => 'tbl_1', 'name' => 'Table 1', 'solution_id' => solution_id || 'sol_123' },
      { 'id' => 'tbl_2', 'name' => 'Table 2', 'solution_id' => solution_id || 'sol_456' }
    ]
  end
end
