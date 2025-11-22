# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite/cache/layer'
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
    @cache.track_cache_miss(table_id)
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

  # ========== Member Caching Tests ==========

  def test_cache_members
    members = create_test_members
    count = @cache.cache_members(members)
    assert_equal 2, count
  end

  def test_get_cached_members
    members = create_test_members
    @cache.cache_members(members)

    cached = @cache.get_cached_members
    assert cached.is_a?(Array)
    assert_equal 2, cached.size
    assert_equal 'user_1', cached[0]['id']
  end

  def test_get_cached_members_with_query
    members = create_test_members
    @cache.cache_members(members)

    # Search by name
    cached = @cache.get_cached_members(query: 'John')
    assert_equal 1, cached.size
    assert_equal 'John Doe', cached[0]['full_name']
  end

  def test_get_cached_members_with_include_inactive
    members = [
      { 'id' => 'user_1', 'email' => 'active@test.com', 'full_name' => 'Active User', 'deleted_date' => nil },
      { 'id' => 'user_2', 'email' => 'deleted@test.com', 'full_name' => 'Deleted User', 'deleted_date' => '2025-01-01' }
    ]
    @cache.cache_members(members)

    # Without include_inactive - should only return active
    active_only = @cache.get_cached_members(include_inactive: false)
    assert_equal 1, active_only.size
    assert_equal 'user_1', active_only[0]['id']

    # With include_inactive - should return all
    all_members = @cache.get_cached_members(include_inactive: true)
    assert_equal 2, all_members.size
  end

  def test_get_cached_members_when_expired
    members = create_test_members
    @cache.cache_members(members, ttl: -1)

    cached = @cache.get_cached_members
    assert_nil cached
  end

  def test_members_cache_valid
    members = create_test_members
    @cache.cache_members(members)

    assert @cache.send(:members_cache_valid?)
  end

  def test_invalidate_members_cache
    members = create_test_members
    @cache.cache_members(members)

    @cache.send(:invalidate_members_cache)

    refute @cache.send(:members_cache_valid?)
  end

  def test_refresh_cache_members
    members = create_test_members
    @cache.cache_members(members)

    result = @cache.refresh_cache('members')

    assert_equal 'refresh', result['operation']
    assert_includes result['message'], 'Members'
    refute @cache.send(:members_cache_valid?)
  end

  # ========== Team Caching Tests ==========

  def test_cache_teams
    teams = create_test_teams
    count = @cache.cache_teams(teams)
    assert_equal 2, count
  end

  def test_get_cached_teams
    teams = create_test_teams
    @cache.cache_teams(teams)

    cached = @cache.get_cached_teams
    assert cached.is_a?(Array)
    assert_equal 2, cached.size
    assert_equal 'team_1', cached[0]['id']
    assert_equal 'Team One', cached[0]['name']
  end

  def test_get_cached_teams_when_expired
    teams = create_test_teams
    @cache.cache_teams(teams, ttl: -1)

    cached = @cache.get_cached_teams
    assert_nil cached
  end

  def test_get_cached_team
    teams = create_test_teams
    @cache.cache_teams(teams)

    cached = @cache.get_cached_team('team_1')
    assert cached.is_a?(Hash)
    assert_equal 'team_1', cached['id']
    assert_equal 'Team One', cached['name']
    assert_equal %w[user_1 user_2], cached['members']
  end

  def test_get_cached_team_not_found
    teams = create_test_teams
    @cache.cache_teams(teams)

    cached = @cache.get_cached_team('nonexistent')
    assert_nil cached
  end

  def test_teams_cache_valid
    teams = create_test_teams
    @cache.cache_teams(teams)

    assert @cache.send(:teams_cache_valid?)
  end

  def test_invalidate_teams_cache
    teams = create_test_teams
    @cache.cache_teams(teams)

    @cache.send(:invalidate_teams_cache)

    refute @cache.send(:teams_cache_valid?)
  end

  def test_refresh_cache_teams
    teams = create_test_teams
    @cache.cache_teams(teams)

    result = @cache.refresh_cache('teams')

    assert_equal 'refresh', result['operation']
    assert_includes result['message'], 'Teams'
    refute @cache.send(:teams_cache_valid?)
  end

  # ========== db_execute Error Handling Tests ==========

  def test_db_execute_logs_and_reraises_errors
    # Create a cache with a custom setup that will fail
    error_raised = false
    begin
      @cache.db_execute('SELECT * FROM nonexistent_table_xyz')
    rescue SQLite3::Exception
      error_raised = true
    end

    assert error_raised, 'Should raise SQLite3::Exception for invalid table'
  end

  # ========== record_stat Error Handling Tests ==========

  def test_record_stat_handles_errors_silently
    # Drop the stats table to cause an error
    @cache.db.execute('DROP TABLE cache_stats')

    # Should not raise - should log warning to stderr
    @cache.send(:record_stat, 'test', 'op', 'key', { foo: 'bar' })
  end

  # ========== get_cached_record Tests ==========

  def test_get_cached_record_returns_nil_when_cache_invalid
    result = @cache.get_cached_record('tbl_nonexistent', 'rec_123')
    assert_nil result
  end

  def test_get_cached_record_returns_record_when_found
    table_id = 'tbl_cached_rec'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    result = @cache.get_cached_record(table_id, 'rec_1')
    assert result.is_a?(Hash)
    assert_equal 'rec_1', result['id']
  end

  def test_get_cached_record_returns_nil_when_not_found
    table_id = 'tbl_cached_rec2'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    result = @cache.get_cached_record(table_id, 'rec_nonexistent')
    assert_nil result
  end

  # ========== cache_single_record Tests ==========

  def test_cache_single_record_success
    table_id = 'tbl_single_cache'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    # Now cache a single new record
    new_record = { 'id' => 'rec_new', 'name' => 'New Record', 'status' => { 'value' => 'new' }, 'priority' => 5 }
    # First cache the table structure
    @cache.cache_table_list(nil,
                            [{ 'id' => table_id, 'name' => 'Test Table', 'solution_id' => 'sol_1', 'structure' => structure['structure'] }])

    result = @cache.cache_single_record(table_id, new_record)
    assert result, 'Should return true on success'

    # Verify record was cached
    cached = @cache.get_cached_record(table_id, 'rec_new')
    assert cached
    assert_equal 'rec_new', cached['id']
  end

  def test_cache_single_record_returns_false_for_nil_record
    result = @cache.cache_single_record('tbl_123', nil)
    refute result
  end

  def test_cache_single_record_returns_false_for_record_without_id
    result = @cache.cache_single_record('tbl_123', { 'name' => 'No ID' })
    refute result
  end

  def test_cache_single_record_returns_false_when_no_table_structure
    result = @cache.cache_single_record('tbl_nonexistent', { 'id' => 'rec_1', 'name' => 'Test' })
    refute result
  end

  # ========== delete_cached_record Tests ==========

  def test_delete_cached_record_success
    table_id = 'tbl_delete_cache'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    # Cache the table structure for get_cached_table to work
    @cache.cache_table_list(nil,
                            [{ 'id' => table_id, 'name' => 'Test Table', 'solution_id' => 'sol_1', 'structure' => structure['structure'] }])

    result = @cache.delete_cached_record(table_id, 'rec_1')
    assert result, 'Should return true on success'

    # Verify record was deleted
    query_results = @cache.query(table_id).where(id: 'rec_1').execute
    assert_empty query_results
  end

  def test_delete_cached_record_returns_false_for_nil_record_id
    result = @cache.delete_cached_record('tbl_123', nil)
    refute result
  end

  def test_delete_cached_record_returns_false_when_no_table_structure
    result = @cache.delete_cached_record('tbl_nonexistent', 'rec_123')
    refute result
  end

  # ========== cache_solutions with description as Hash ==========

  def test_cache_solutions_with_description_hash
    solutions = [
      {
        'id' => 'sol_desc_hash',
        'name' => 'Solution With HTML Desc',
        'logo_icon' => 'icon',
        'logo_color' => '#000',
        'description' => { 'html' => '<p>Rich description</p>', 'text' => 'Rich description' }
      }
    ]

    @cache.cache_solutions(solutions)
    cached = @cache.get_cached_solutions

    assert_equal 1, cached.size
    assert_equal '<p>Rich description</p>', cached[0]['description']
  end

  # ========== get_cached_solutions with name filter ==========

  def test_get_cached_solutions_with_name_filter
    solutions = [
      { 'id' => 'sol_1', 'name' => 'Marketing Projects', 'logo_icon' => 'icon', 'logo_color' => '#000' },
      { 'id' => 'sol_2', 'name' => 'Sales Pipeline', 'logo_icon' => 'icon', 'logo_color' => '#000' },
      { 'id' => 'sol_3', 'name' => 'HR Management', 'logo_icon' => 'icon', 'logo_color' => '#000' }
    ]
    @cache.cache_solutions(solutions)

    # Fuzzy search for "Marketing"
    cached = @cache.get_cached_solutions(name: 'Marketing')
    assert_equal 1, cached.size
    assert_equal 'sol_1', cached[0]['id']
  end

  # ========== get_tables_to_warm Edge Cases ==========

  def test_get_tables_to_warm_with_invalid_type_returns_empty
    result = @cache.get_tables_to_warm(tables: 12_345) # Invalid type (Integer)
    assert_equal [], result
  end

  # ========== extract_field_value Additional Field Types ==========

  def test_extract_field_value_lastupdated_field
    field_info = { 'slug' => 's123', 'field_type' => 'lastupdatedfield', 'label' => 'Updated' }
    value = { 'on' => '2025-01-15T12:00:00Z', 'by' => 'user_456' }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-15T12:00:00Z', result['updated_on']
    assert_equal 'user_456', result['updated_by']
  end

  def test_extract_field_value_deleted_date_field
    field_info = { 'slug' => 'deleted', 'field_type' => 'deleted_date', 'label' => 'Deleted' }
    value = { 'date' => '2025-01-15T12:00:00Z', 'deleted_by' => 'user_789' }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-15T12:00:00Z', result['deleted_on']
    assert_equal 'user_789', result['deleted_by']
  end

  def test_extract_field_value_date_field
    field_info = { 'slug' => 'due', 'field_type' => 'datefield', 'label' => 'Due Date' }
    value = { 'date' => '2025-01-20' }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-20', result['due_date']
  end

  def test_extract_field_value_daterange_field
    field_info = { 'slug' => 'period', 'field_type' => 'daterangefield', 'label' => 'Period' }
    value = {
      'from_date' => { 'date' => '2025-01-01' },
      'to_date' => { 'date' => '2025-01-31' }
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-01', result['period_from']
    assert_equal '2025-01-31', result['period_to']
  end

  def test_extract_field_value_duedate_field
    field_info = { 'slug' => 'deadline', 'field_type' => 'duedatefield', 'label' => 'Deadline' }
    value = {
      'from_date' => { 'date' => '2025-01-15' },
      'to_date' => { 'date' => '2025-01-20' },
      'is_overdue' => true,
      'status_is_completed' => false
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '2025-01-15', result['deadline_from']
    assert_equal '2025-01-20', result['deadline_to']
    assert_equal 1, result['deadline_is_overdue']
    assert_equal 0, result['deadline_is_completed']
  end

  def test_extract_field_value_address_field
    field_info = { 'slug' => 'address', 'field_type' => 'addressfield', 'label' => 'Address' }
    value = {
      'sys_root' => '123 Main St, City, State',
      'street' => '123 Main St',
      'city' => 'City'
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal '123 Main St, City, State', result['address_text']
    assert result['address_json'].include?('123 Main St')
  end

  def test_extract_field_value_fullname_field
    field_info = { 'slug' => 'contact', 'field_type' => 'fullnamefield', 'label' => 'Contact' }
    value = {
      'sys_root' => 'John Doe',
      'first_name' => 'John',
      'last_name' => 'Doe'
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 'John Doe', result['contact']
    assert result['contact_json'].include?('John')
  end

  def test_extract_field_value_smartdoc_field
    field_info = { 'slug' => 'notes', 'field_type' => 'smartdocfield', 'label' => 'Notes' }
    value = {
      'preview' => 'This is a preview...',
      'data' => { 'type' => 'doc', 'content' => [] }
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 'This is a preview...', result['notes_preview']
    assert result['notes_json'].include?('preview')
  end

  def test_extract_field_value_checklist_field
    field_info = { 'slug' => 'tasks', 'field_type' => 'checklistfield', 'label' => 'Tasks' }
    value = {
      'total_items' => 5,
      'completed_items' => 3,
      'items' => []
    }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 5, result['tasks_total']
    assert_equal 3, result['tasks_completed']
    assert result['tasks_json']
  end

  def test_extract_field_value_vote_field
    field_info = { 'slug' => 'votes', 'field_type' => 'votefield', 'label' => 'Votes' }
    value = { 'total_votes' => 10, 'voters' => [] }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 10, result['votes_count']
    assert result['votes_json']
  end

  def test_extract_field_value_timetracking_field
    field_info = { 'slug' => 'time', 'field_type' => 'timetrackingfield', 'label' => 'Time' }
    value = { 'total_duration' => 3600, 'entries' => [] }

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 3600, result['time_total']
    assert result['time_json']
  end

  def test_extract_field_value_duration_field
    field_info = { 'slug' => 'duration', 'field_type' => 'durationfield', 'label' => 'Duration' }
    value = 7200.5

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 7200.5, result['duration']
  end

  def test_extract_field_value_currency_field
    field_info = { 'slug' => 'price', 'field_type' => 'currencyfield', 'label' => 'Price' }
    value = 99.99

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 99.99, result['price']
  end

  def test_extract_field_value_percent_field
    field_info = { 'slug' => 'progress', 'field_type' => 'percentfield', 'label' => 'Progress' }
    value = 75.5

    result = @cache.send(:extract_field_value, field_info, value)

    assert_equal 75.5, result['progress']
  end

  def test_extract_field_value_email_field
    field_info = { 'slug' => 'emails', 'field_type' => 'emailfield', 'label' => 'Emails' }
    value = ['test@example.com', 'other@example.com']

    result = @cache.send(:extract_field_value, field_info, value)

    assert result['emails'].is_a?(String) # JSON
    parsed = JSON.parse(result['emails'])
    assert_equal 2, parsed.size
  end

  # ========== find_matching_value Tests ==========

  def test_find_matching_value_single_column
    field_info = { 'slug' => 'name', 'field_type' => 'textfield', 'label' => 'Name' }
    extracted_values = { 'name' => 'Test Value' }

    result = @cache.send(:find_matching_value, extracted_values, 'name', field_info)

    assert_equal 'Test Value', result
  end

  def test_find_matching_value_firstcreated_on
    field_info = { 'slug' => 'first', 'field_type' => 'firstcreatedfield', 'label' => 'Created' }
    extracted_values = { 'created_on' => '2025-01-01', 'created_by' => 'user_1' }

    result = @cache.send(:find_matching_value, extracted_values, 'created_on', field_info)

    assert_equal '2025-01-01', result
  end

  def test_find_matching_value_firstcreated_by
    field_info = { 'slug' => 'first', 'field_type' => 'firstcreatedfield', 'label' => 'Created' }
    extracted_values = { 'created_on' => '2025-01-01', 'created_by' => 'user_1' }

    result = @cache.send(:find_matching_value, extracted_values, 'created_by', field_info)

    assert_equal 'user_1', result
  end

  def test_find_matching_value_lastupdated_on
    field_info = { 'slug' => 'updated', 'field_type' => 'lastupdatedfield', 'label' => 'Modified' }
    extracted_values = { 'modified_on' => '2025-01-15', 'modified_by' => 'user_2' }

    result = @cache.send(:find_matching_value, extracted_values, 'modified_on', field_info)

    assert_equal '2025-01-15', result
  end

  def test_find_matching_value_lastupdated_by
    field_info = { 'slug' => 'updated', 'field_type' => 'lastupdatedfield', 'label' => 'Modified' }
    extracted_values = { 'modified_on' => '2025-01-15', 'modified_by' => 'user_2' }

    result = @cache.send(:find_matching_value, extracted_values, 'modified_by', field_info)

    assert_equal 'user_2', result
  end

  def test_find_matching_value_deleted_date_on
    field_info = { 'slug' => 'del', 'field_type' => 'deleted_date', 'label' => 'Deleted' }
    extracted_values = { 'deleted_on' => '2025-01-20', 'deleted_by' => 'user_3' }

    result = @cache.send(:find_matching_value, extracted_values, 'deleted_on', field_info)

    assert_equal '2025-01-20', result
  end

  def test_find_matching_value_deleted_date_by
    field_info = { 'slug' => 'del', 'field_type' => 'deleted_date', 'label' => 'Deleted' }
    extracted_values = { 'deleted_on' => '2025-01-20', 'deleted_by' => 'user_3' }

    result = @cache.send(:find_matching_value, extracted_values, 'deleted_by', field_info)

    assert_equal 'user_3', result
  end

  def test_find_matching_value_statusfield_value
    field_info = { 'slug' => 'status', 'field_type' => 'statusfield', 'label' => 'Status' }
    extracted_values = { 'status' => 'Active', 'status_updated_on' => '2025-01-01' }

    result = @cache.send(:find_matching_value, extracted_values, 'status', field_info)

    assert_equal 'Active', result
  end

  def test_find_matching_value_statusfield_updated_on
    field_info = { 'slug' => 'status', 'field_type' => 'statusfield', 'label' => 'Status' }
    extracted_values = { 'status' => 'Active', 'status_updated_on' => '2025-01-01' }

    result = @cache.send(:find_matching_value, extracted_values, 'status_updated_on', field_info)

    assert_equal '2025-01-01', result
  end

  def test_find_matching_value_daterange_from
    field_info = { 'slug' => 'period', 'field_type' => 'daterangefield', 'label' => 'Period' }
    extracted_values = { 'period_from' => '2025-01-01', 'period_to' => '2025-01-31' }

    result = @cache.send(:find_matching_value, extracted_values, 'period_from', field_info)

    assert_equal '2025-01-01', result
  end

  def test_find_matching_value_daterange_to
    field_info = { 'slug' => 'period', 'field_type' => 'daterangefield', 'label' => 'Period' }
    extracted_values = { 'period_from' => '2025-01-01', 'period_to' => '2025-01-31' }

    result = @cache.send(:find_matching_value, extracted_values, 'period_to', field_info)

    assert_equal '2025-01-31', result
  end

  def test_find_matching_value_duedate_overdue
    field_info = { 'slug' => 'due', 'field_type' => 'duedatefield', 'label' => 'Due' }
    extracted_values = {
      'due_from' => '2025-01-01',
      'due_to' => '2025-01-15',
      'due_is_overdue' => 1,
      'due_is_completed' => 0
    }

    result = @cache.send(:find_matching_value, extracted_values, 'due_is_overdue', field_info)

    assert_equal 1, result
  end

  def test_find_matching_value_duedate_completed
    field_info = { 'slug' => 'due', 'field_type' => 'duedatefield', 'label' => 'Due' }
    extracted_values = {
      'due_from' => '2025-01-01',
      'due_to' => '2025-01-15',
      'due_is_overdue' => 0,
      'due_is_completed' => 1
    }

    result = @cache.send(:find_matching_value, extracted_values, 'due_is_completed', field_info)

    assert_equal 1, result
  end

  def test_find_matching_value_suffix_text
    field_info = { 'slug' => 'addr', 'field_type' => 'addressfield', 'label' => 'Address' }
    extracted_values = { 'address_text' => '123 Main St', 'address_json' => '{}' }

    result = @cache.send(:find_matching_value, extracted_values, 'address_text', field_info)

    assert_equal '123 Main St', result
  end

  def test_find_matching_value_suffix_json
    field_info = { 'slug' => 'addr', 'field_type' => 'addressfield', 'label' => 'Address' }
    extracted_values = { 'address_text' => '123 Main St', 'address_json' => '{"city":"NYC"}' }

    result = @cache.send(:find_matching_value, extracted_values, 'address_json', field_info)

    assert_equal '{"city":"NYC"}', result
  end

  def test_find_matching_value_suffix_preview
    field_info = { 'slug' => 'doc', 'field_type' => 'smartdocfield', 'label' => 'Doc' }
    extracted_values = { 'doc_preview' => 'Preview text', 'doc_json' => '{}' }

    result = @cache.send(:find_matching_value, extracted_values, 'doc_preview', field_info)

    assert_equal 'Preview text', result
  end

  def test_find_matching_value_suffix_total
    field_info = { 'slug' => 'check', 'field_type' => 'checklistfield', 'label' => 'Check' }
    extracted_values = { 'check_json' => '[]', 'check_total' => 5, 'check_completed' => 3 }

    result = @cache.send(:find_matching_value, extracted_values, 'check_total', field_info)

    assert_equal 5, result
  end

  def test_find_matching_value_suffix_completed
    field_info = { 'slug' => 'check', 'field_type' => 'checklistfield', 'label' => 'Check' }
    extracted_values = { 'check_json' => '[]', 'check_total' => 5, 'check_completed' => 3 }

    result = @cache.send(:find_matching_value, extracted_values, 'check_completed', field_info)

    assert_equal 3, result
  end

  def test_find_matching_value_suffix_count
    field_info = { 'slug' => 'vote', 'field_type' => 'votefield', 'label' => 'Vote' }
    extracted_values = { 'vote_count' => 10, 'vote_json' => '[]' }

    result = @cache.send(:find_matching_value, extracted_values, 'vote_count', field_info)

    assert_equal 10, result
  end

  def test_find_matching_value_exact_match
    field_info = { 'slug' => 'custom', 'field_type' => 'textfield', 'label' => 'Custom' }
    extracted_values = { 'exact_column_name' => 'exact value' }

    result = @cache.send(:find_matching_value, extracted_values, 'exact_column_name', field_info)

    assert_equal 'exact value', result
  end

  # ========== Cache Status Error Handling ==========

  def test_get_solutions_cache_status_handles_invalid_timestamp
    # Insert a solution with invalid timestamp
    @cache.db.execute(
      "INSERT INTO cached_solutions (id, name, logo_icon, logo_color, cached_at, expires_at)
       VALUES ('sol_invalid', 'Invalid', 'icon', '#000', '2025-01-01', 'invalid-timestamp')"
    )

    status = @cache.get_cache_status
    # Should handle gracefully without crashing
    assert status.is_a?(Hash)
  end

  def test_get_tables_cache_status_handles_invalid_timestamp
    # Insert a table with invalid timestamp
    @cache.db.execute(
      "INSERT INTO cached_tables (id, name, solution_id, cached_at, expires_at)
       VALUES ('tbl_invalid', 'Invalid', 'sol_1', '2025-01-01', 'invalid-timestamp')"
    )

    status = @cache.get_cache_status
    assert status.is_a?(Hash)
  end

  def test_get_members_cache_status_handles_invalid_timestamp
    # Insert a member with invalid timestamp
    @cache.db.execute(
      "INSERT INTO cached_members (id, email, cached_at, expires_at)
       VALUES ('user_invalid', 'test@test.com', '2025-01-01', 'invalid-timestamp')"
    )

    status = @cache.get_cache_status
    assert status.is_a?(Hash)
  end

  def test_get_teams_cache_status_handles_invalid_timestamp
    # Insert a team with invalid timestamp
    @cache.db.execute(
      "INSERT INTO cached_teams (id, name, cached_at, expires_at)
       VALUES ('team_invalid', 'Invalid', '2025-01-01', 'invalid-timestamp')"
    )

    status = @cache.get_cache_status
    assert status.is_a?(Hash)
  end

  def test_get_records_cache_status_handles_zero_timestamp
    # Cache some records
    table_id = 'tbl_zero_ts'
    structure = create_test_structure
    records = create_test_records
    @cache.cache_table_records(table_id, structure, records)

    # Manually set expires_at to 0 (invalidated)
    schema = @cache.send(:get_cached_table_schema, table_id)
    @cache.db.execute("UPDATE #{schema['sql_table_name']} SET expires_at = '0'")

    status = @cache.get_cache_status(table_id: table_id)
    # Should handle gracefully - records should be empty or show as invalid
    assert status.is_a?(Hash)
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

  def create_test_members
    [
      { 'id' => 'user_1', 'email' => 'john@test.com', 'full_name' => 'John Doe', 'first_name' => 'John', 'last_name' => 'Doe' },
      { 'id' => 'user_2', 'email' => 'jane@test.com', 'full_name' => 'Jane Smith', 'first_name' => 'Jane', 'last_name' => 'Smith' }
    ]
  end

  def create_test_teams
    [
      { 'id' => 'team_1', 'name' => 'Team One', 'description' => 'First team', 'members' => %w[user_1 user_2] },
      { 'id' => 'team_2', 'name' => 'Team Two', 'description' => 'Second team', 'members' => ['user_3'] }
    ]
  end
end
