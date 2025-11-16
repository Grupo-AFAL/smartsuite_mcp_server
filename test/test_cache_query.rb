# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite/cache/query'
require_relative '../lib/smartsuite/cache/layer'
require 'sqlite3'
require 'fileutils'
require 'json'

class TestCacheQuery < Minitest::Test
  def setup
    # Create a temporary database for testing
    @test_db_path = File.join(Dir.tmpdir, "test_cache_query_#{rand(100_000)}.db")
    @cache = SmartSuite::Cache::Layer.new(db_path: @test_db_path)

    # Create test table with sample data
    create_test_table_and_data
  end

  def teardown
    @cache.close
    FileUtils.rm_f(@test_db_path) if File.exist?(@test_db_path)
  end

  # Test simple equality where clause
  def test_where_simple_equality
    query = @cache.query('tbl_test_123')
                  .where(status: 'active')

    results = query.execute

    assert results.is_a?(Array), "Should return array"
    assert results.all? { |r| r['status'] == 'active' }, "All results should match status"
  end

  # Test multiple where clauses (AND)
  def test_where_multiple_conditions
    query = @cache.query('tbl_test_123')
                  .where(status: 'active')
                  .where(priority: { gte: 3 })

    results = query.execute

    assert results.all? { |r| r['status'] == 'active' && r['priority'] >= 3 },
           "Should match all conditions"
  end

  # Test greater than operator
  def test_where_greater_than
    query = @cache.query('tbl_test_123')
                  .where(priority: { gt: 2 })

    results = query.execute

    assert results.all? { |r| r['priority'] > 2 }, "Should match greater than"
  end

  # Test greater than or equal operator
  def test_where_greater_than_or_equal
    query = @cache.query('tbl_test_123')
                  .where(priority: { gte: 3 })

    results = query.execute

    assert results.all? { |r| r['priority'] >= 3 }, "Should match gte"
  end

  # Test less than operator
  def test_where_less_than
    query = @cache.query('tbl_test_123')
                  .where(priority: { lt: 3 })

    results = query.execute

    assert results.all? { |r| r['priority'] < 3 }, "Should match less than"
  end

  # Test less than or equal operator
  def test_where_less_than_or_equal
    query = @cache.query('tbl_test_123')
                  .where(priority: { lte: 2 })

    results = query.execute

    assert results.all? { |r| r['priority'] <= 2 }, "Should match lte"
  end

  # Test not equal operator
  def test_where_not_equal
    query = @cache.query('tbl_test_123')
                  .where(status: { ne: 'archived' })

    results = query.execute

    assert results.all? { |r| r['status'] != 'archived' }, "Should match not equal"
  end

  # Test contains operator
  def test_where_contains
    query = @cache.query('tbl_test_123')
                  .where(name: { contains: 'Task' })

    results = query.execute

    assert results.all? { |r| r['name'].include?('Task') }, "Should match contains"
  end

  # Test starts_with operator
  def test_where_starts_with
    query = @cache.query('tbl_test_123')
                  .where(name: { starts_with: 'Task' })

    results = query.execute

    assert results.all? { |r| r['name'].start_with?('Task') }, "Should match starts_with"
  end

  # Test ends_with operator
  def test_where_ends_with
    query = @cache.query('tbl_test_123')
                  .where(name: { ends_with: '1' })

    results = query.execute

    assert results.all? { |r| r['name'].end_with?('1') }, "Should match ends_with"
  end

  # Test in operator
  def test_where_in_operator
    query = @cache.query('tbl_test_123')
                  .where(status: { in: %w[active pending] })

    results = query.execute

    assert results.all? { |r| %w[active pending].include?(r['status']) }, "Should match in"
  end

  # Test not_in operator
  def test_where_not_in_operator
    query = @cache.query('tbl_test_123')
                  .where(status: { not_in: ['archived'] })

    results = query.execute

    assert results.all? { |r| !['archived'].include?(r['status']) }, "Should match not_in"
  end

  # Test between operator
  def test_where_between_operator
    query = @cache.query('tbl_test_123')
                  .where(priority: { between: { min: 2, max: 4 } })

    results = query.execute

    assert results.all? { |r| r['priority'] >= 2 && r['priority'] <= 4 }, "Should match between"
  end

  # Test is_null operator
  def test_where_is_null
    # Insert a record with null description
    sql_table_name = @cache.get_cached_table_schema('tbl_test_123')['sql_table_name']
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, description, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['rec_null', 'Null Test', 'active', 1, nil, Time.now.to_i, Time.now.to_i + 3600]
    )

    query = @cache.query('tbl_test_123')
                  .where(description: { is_null: true })

    results = query.execute

    assert results.any?, "Should find records with null description"
    assert results.all? { |r| r['description'].nil? }, "Should match is_null"
  end

  # Test is_not_null operator
  def test_where_is_not_null
    query = @cache.query('tbl_test_123')
                  .where(description: { is_not_null: true })

    results = query.execute

    assert results.all? { |r| !r['description'].nil? }, "Should match is_not_null"
  end

  # Test is_empty operator for text fields
  def test_where_is_empty_text
    # Insert a record with empty description
    sql_table_name = @cache.get_cached_table_schema('tbl_test_123')['sql_table_name']
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, description, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['rec_empty', 'Empty Test', 'active', 1, '', Time.now.to_i, Time.now.to_i + 3600]
    )

    query = @cache.query('tbl_test_123')
                  .where(description: { is_empty: true })

    results = query.execute

    assert results.any?, "Should find records with empty description"
  end

  # Test is_not_empty operator for text fields
  def test_where_is_not_empty_text
    query = @cache.query('tbl_test_123')
                  .where(name: { is_not_empty: true })

    results = query.execute

    assert results.all? { |r| !r['name'].nil? && r['name'] != '' }, "Should match is_not_empty"
  end

  # Test order by ascending
  def test_order_ascending
    query = @cache.query('tbl_test_123')
                  .order('priority', 'ASC')

    results = query.execute

    priorities = results.map { |r| r['priority'] }
    assert_equal priorities, priorities.sort, "Should be sorted ascending"
  end

  # Test order by descending
  def test_order_descending
    query = @cache.query('tbl_test_123')
                  .order('priority', 'DESC')

    results = query.execute

    priorities = results.map { |r| r['priority'] }
    assert_equal priorities, priorities.sort.reverse, "Should be sorted descending"
  end

  # Test limit
  def test_limit
    query = @cache.query('tbl_test_123')
                  .limit(2)

    results = query.execute

    assert_equal 2, results.size, "Should return only 2 results"
  end

  # Test offset
  def test_offset
    # Get all results sorted by priority
    all_results = @cache.query('tbl_test_123')
                        .order('priority', 'ASC')
                        .execute

    # Get results with offset
    offset_results = @cache.query('tbl_test_123')
                           .order('priority', 'ASC')
                           .offset(1)
                           .execute

    # Should skip first result
    assert_equal all_results[1..-1].size, offset_results.size, "Should skip first result"
    assert_equal all_results[1]['id'], offset_results[0]['id'], "Should start from second result"
  end

  # Test limit with offset (pagination)
  def test_limit_with_offset
    query = @cache.query('tbl_test_123')
                  .order('priority', 'ASC')
                  .limit(2)
                  .offset(1)

    results = query.execute

    assert_equal 2, results.size, "Should return 2 results"
  end

  # Test chaining: where + order + limit
  def test_chaining_where_order_limit
    query = @cache.query('tbl_test_123')
                  .where(status: 'active')
                  .order('priority', 'DESC')
                  .limit(2)

    results = query.execute

    assert results.size <= 2, "Should respect limit"
    assert results.all? { |r| r['status'] == 'active' }, "Should match where"

    # Check ordering
    if results.size > 1
      assert results[0]['priority'] >= results[1]['priority'], "Should be ordered descending"
    end
  end

  # Test count without filters
  def test_count_all
    count = @cache.query('tbl_test_123').count

    assert count > 0, "Should count all records"
    assert_equal 5, count, "Should have 5 test records"
  end

  # Test count with filters
  def test_count_with_filter
    count = @cache.query('tbl_test_123')
                  .where(status: 'active')
                  .count

    active_count = @cache.query('tbl_test_123')
                         .where(status: 'active')
                         .execute
                         .size

    assert_equal active_count, count, "Count should match filtered results"
  end

  # Test error handling: table not cached
  def test_error_table_not_cached
    error = assert_raises(RuntimeError) do
      @cache.query('tbl_nonexistent')
            .where(status: 'active')
            .execute
    end

    assert_includes error.message, 'not cached', "Should raise error for uncached table"
  end

  # Test unknown field handling
  def test_unknown_field_skip
    # Should skip unknown field and not crash
    query = @cache.query('tbl_test_123')
                  .where(nonexistent_field: 'value')
                  .where(status: 'active')

    results = query.execute

    # Should still work with valid fields
    assert results.all? { |r| r['status'] == 'active' }, "Should process valid fields"
  end

  # Test has_any_of operator (for JSON arrays)
  def test_where_has_any_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema('tbl_test_123')['sql_table_name']
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['rec_tags', 'Tagged Task', 'active', 1, '["urgent", "bug"]', Time.now.to_i, Time.now.to_i + 3600]
    )

    query = @cache.query('tbl_test_123')
                  .where(tags: { has_any_of: ['urgent'] })

    results = query.execute

    assert results.any? { |r| r['id'] == 'rec_tags' }, "Should find record with tag"
  end

  # Test has_all_of operator (for JSON arrays)
  def test_where_has_all_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema('tbl_test_123')['sql_table_name']
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['rec_multi_tags', 'Multi Tagged', 'active', 1, '["urgent", "bug", "feature"]',
       Time.now.to_i, Time.now.to_i + 3600]
    )

    query = @cache.query('tbl_test_123')
                  .where(tags: { has_all_of: %w[urgent bug] })

    results = query.execute

    assert results.any? { |r| r['id'] == 'rec_multi_tags' }, "Should find record with all tags"
  end

  # Test has_none_of operator (for JSON arrays)
  def test_where_has_none_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema('tbl_test_123')['sql_table_name']
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['rec_clean', 'Clean Task', 'active', 1, '["normal"]', Time.now.to_i, Time.now.to_i + 3600]
    )

    query = @cache.query('tbl_test_123')
                  .where(tags: { has_none_of: %w[urgent bug] })

    results = query.execute

    assert results.any? { |r| r['id'] == 'rec_clean' }, "Should find record without specified tags"
  end

  private

  # Create test table and populate with sample data
  def create_test_table_and_data
    table_id = 'tbl_test_123'

    # Mock table structure
    structure = {
      'name' => 'Test Table',
      'structure' => [
        { 'slug' => 'name', 'label' => 'Name', 'field_type' => 'textfield' },
        { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield' },
        { 'slug' => 'priority', 'label' => 'Priority', 'field_type' => 'numberfield' },
        { 'slug' => 'description', 'label' => 'Description', 'field_type' => 'textarea' },
        { 'slug' => 'tags', 'label' => 'Tags', 'field_type' => 'multipleselectfield' }
      ]
    }

    # Create cache table
    sql_table_name = @cache.create_cache_table(table_id, structure)

    # Insert sample records
    now = Time.now.to_i
    expires = now + 3600

    sample_data = [
      ['rec_1', 'Task 1', 'active', 1, 'First task', '[]'],
      ['rec_2', 'Task 2', 'active', 3, 'Second task', '[]'],
      ['rec_3', 'Task 3', 'pending', 2, 'Third task', '[]'],
      ['rec_4', 'Task 4', 'archived', 4, 'Fourth task', '[]'],
      ['rec_5', 'Project 1', 'active', 5, 'Fifth task', '[]']
    ]

    sample_data.each do |data|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, name, status, priority, description, tags, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        data + [now, expires]
      )
    end
  end
end
