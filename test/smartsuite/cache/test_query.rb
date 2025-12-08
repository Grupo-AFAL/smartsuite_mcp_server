# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/smart_suite/cache/query"
require_relative "../../../lib/smart_suite/cache/layer"
require "sqlite3"
require "fileutils"
require "json"

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
    query = @cache.query("tbl_test_123")
                  .where(status: "active")

    results = query.execute

    assert results.is_a?(Array), "Should return array"
    assert results.all? { |r| r["status"] == "active" }, "All results should match status"
  end

  # Test multiple where clauses (AND)
  def test_where_multiple_conditions
    query = @cache.query("tbl_test_123")
                  .where(status: "active")
                  .where(priority: { gte: 3 })

    results = query.execute

    assert results.all? { |r| r["status"] == "active" && r["priority"] >= 3 },
           "Should match all conditions"
  end

  # Test greater than operator
  def test_where_greater_than
    query = @cache.query("tbl_test_123")
                  .where(priority: { gt: 2 })

    results = query.execute

    assert results.all? { |r| r["priority"] > 2 }, "Should match greater than"
  end

  # Test greater than or equal operator
  def test_where_greater_than_or_equal
    query = @cache.query("tbl_test_123")
                  .where(priority: { gte: 3 })

    results = query.execute

    assert results.all? { |r| r["priority"] >= 3 }, "Should match gte"
  end

  # Test less than operator
  def test_where_less_than
    query = @cache.query("tbl_test_123")
                  .where(priority: { lt: 3 })

    results = query.execute

    assert results.all? { |r| r["priority"] < 3 }, "Should match less than"
  end

  # Test less than or equal operator
  def test_where_less_than_or_equal
    query = @cache.query("tbl_test_123")
                  .where(priority: { lte: 2 })

    results = query.execute

    assert results.all? { |r| r["priority"] <= 2 }, "Should match lte"
  end

  # Test not equal operator
  def test_where_not_equal
    query = @cache.query("tbl_test_123")
                  .where(status: { ne: "archived" })

    results = query.execute

    assert results.all? { |r| r["status"] != "archived" }, "Should match not equal"
  end

  # Test contains operator
  def test_where_contains
    query = @cache.query("tbl_test_123")
                  .where(name: { contains: "Task" })

    results = query.execute

    assert results.all? { |r| r["name"].include?("Task") }, "Should match contains"
  end

  # Test starts_with operator
  def test_where_starts_with
    query = @cache.query("tbl_test_123")
                  .where(name: { starts_with: "Task" })

    results = query.execute

    assert results.all? { |r| r["name"].start_with?("Task") }, "Should match starts_with"
  end

  # Test ends_with operator
  def test_where_ends_with
    query = @cache.query("tbl_test_123")
                  .where(name: { ends_with: "1" })

    results = query.execute

    assert results.all? { |r| r["name"].end_with?("1") }, "Should match ends_with"
  end

  # Test in operator
  def test_where_in_operator
    query = @cache.query("tbl_test_123")
                  .where(status: { in: %w[active pending] })

    results = query.execute

    assert results.all? { |r| %w[active pending].include?(r["status"]) }, "Should match in"
  end

  # Test not_in operator
  def test_where_not_in_operator
    query = @cache.query("tbl_test_123")
                  .where(status: { not_in: [ "archived" ] })

    results = query.execute

    assert results.all? { |r| ![ "archived" ].include?(r["status"]) }, "Should match not_in"
  end

  # Test between operator
  def test_where_between_operator
    query = @cache.query("tbl_test_123")
                  .where(priority: { between: { min: 2, max: 4 } })

    results = query.execute

    assert results.all? { |r| r["priority"].between?(2, 4) }, "Should match between"
  end

  # Test is_null operator
  def test_where_is_null
    # Insert a record with null description
    sql_table_name = @cache.get_cached_table_schema("tbl_test_123")["sql_table_name"]
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, description, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ "rec_null", "Null Test", "active", 1, nil, Time.now.to_i, Time.now.to_i + 3600 ]
    )

    query = @cache.query("tbl_test_123")
                  .where(description: { is_null: true })

    results = query.execute

    assert results.any?, "Should find records with null description"
    assert results.all? { |r| r["description"].nil? }, "Should match is_null"
  end

  # Test is_not_null operator
  def test_where_is_not_null
    query = @cache.query("tbl_test_123")
                  .where(description: { is_not_null: true })

    results = query.execute

    assert results.all? { |r| !r["description"].nil? }, "Should match is_not_null"
  end

  # Test is_empty operator for text fields
  def test_where_is_empty_text
    # Insert a record with empty description
    sql_table_name = @cache.get_cached_table_schema("tbl_test_123")["sql_table_name"]
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, description, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ "rec_empty", "Empty Test", "active", 1, "", Time.now.to_i, Time.now.to_i + 3600 ]
    )

    query = @cache.query("tbl_test_123")
                  .where(description: { is_empty: true })

    results = query.execute

    assert results.any?, "Should find records with empty description"
  end

  # Test is_not_empty operator for text fields
  def test_where_is_not_empty_text
    query = @cache.query("tbl_test_123")
                  .where(name: { is_not_empty: true })

    results = query.execute

    assert results.all? { |r| !r["name"].nil? && r["name"] != "" }, "Should match is_not_empty"
  end

  # Test order by ascending
  def test_order_ascending
    query = @cache.query("tbl_test_123")
                  .order("priority", "ASC")

    results = query.execute

    priorities = results.map { |r| r["priority"] }
    assert_equal priorities, priorities.sort, "Should be sorted ascending"
  end

  # Test order by descending
  def test_order_descending
    query = @cache.query("tbl_test_123")
                  .order("priority", "DESC")

    results = query.execute

    priorities = results.map { |r| r["priority"] }
    assert_equal priorities, priorities.sort.reverse, "Should be sorted descending"
  end

  # Test limit
  def test_limit
    query = @cache.query("tbl_test_123")
                  .limit(2)

    results = query.execute

    assert_equal 2, results.size, "Should return only 2 results"
  end

  # Test offset
  def test_offset
    # Get all results sorted by priority
    all_results = @cache.query("tbl_test_123")
                        .order("priority", "ASC")
                        .execute

    # Get results with offset
    offset_results = @cache.query("tbl_test_123")
                           .order("priority", "ASC")
                           .offset(1)
                           .execute

    # Should skip first result
    assert_equal all_results[1..].size, offset_results.size, "Should skip first result"
    assert_equal all_results[1]["id"], offset_results[0]["id"], "Should start from second result"
  end

  # Test limit with offset (pagination)
  def test_limit_with_offset
    query = @cache.query("tbl_test_123")
                  .order("priority", "ASC")
                  .limit(2)
                  .offset(1)

    results = query.execute

    assert_equal 2, results.size, "Should return 2 results"
  end

  # Test chaining: where + order + limit
  def test_chaining_where_order_limit
    query = @cache.query("tbl_test_123")
                  .where(status: "active")
                  .order("priority", "DESC")
                  .limit(2)

    results = query.execute

    assert results.size <= 2, "Should respect limit"
    assert results.all? { |r| r["status"] == "active" }, "Should match where"

    # Check ordering
    return unless results.size > 1

    assert results[0]["priority"] >= results[1]["priority"], "Should be ordered descending"
  end

  # Test count without filters
  def test_count_all
    count = @cache.query("tbl_test_123").count

    assert count.positive?, "Should count all records"
    assert_equal 5, count, "Should have 5 test records"
  end

  # Test count with filters
  def test_count_with_filter
    count = @cache.query("tbl_test_123")
                  .where(status: "active")
                  .count

    active_count = @cache.query("tbl_test_123")
                         .where(status: "active")
                         .execute
                         .size

    assert_equal active_count, count, "Count should match filtered results"
  end

  # Test error handling: table not cached
  def test_error_table_not_cached
    error = assert_raises(RuntimeError) do
      @cache.query("tbl_nonexistent")
            .where(status: "active")
            .execute
    end

    assert_includes error.message, "not cached", "Should raise error for uncached table"
  end

  # Test unknown field handling
  def test_unknown_field_skip
    # Should skip unknown field and not crash
    query = @cache.query("tbl_test_123")
                  .where(nonexistent_field: "value")
                  .where(status: "active")

    results = query.execute

    # Should still work with valid fields
    assert results.all? { |r| r["status"] == "active" }, "Should process valid fields"
  end

  # ============================================================================
  # REGRESSION TESTS: Empty Field Values in Query Results
  # ============================================================================
  # Bug: map_column_names_to_field_slugs didn't correctly preserve empty/null values
  # Fix: Ensured all fields are present in results, even if nil, empty string, or zero

  # Test that nil field values are preserved in query results
  def test_empty_fields_preserved_nil_values
    # Create table with records containing nil values
    table_id = "tbl_empty_test"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "description", "label" => "Description", "field_type" => "textarea" },
        { "slug" => "priority", "label" => "Priority", "field_type" => "numberfield" }
      ]
    }
    records = [
      { "id" => "rec_1", "title" => "Task 1", "description" => nil, "priority" => nil }
    ]
    @cache.cache_table_records(table_id, structure, records)

    results = @cache.query(table_id).execute

    # Verify all fields present
    assert_equal 1, results.size
    record = results.first

    assert record.key?("title"), "Should have title field"
    assert record.key?("description"), "Should have description field even if nil"
    assert record.key?("priority"), "Should have priority field even if nil"

    # Verify nil values preserved
    assert_equal "Task 1", record["title"]
    assert_nil record["description"], "Should preserve nil for description"
    assert_nil record["priority"], "Should preserve nil for priority"
  end

  # Test that empty string values are preserved
  def test_empty_fields_preserved_empty_strings
    table_id = "tbl_empty_string_test"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "description", "label" => "Description", "field_type" => "textarea" }
      ]
    }
    records = [
      { "id" => "rec_1", "title" => "", "description" => "" }
    ]
    @cache.cache_table_records(table_id, structure, records)

    results = @cache.query(table_id).execute
    record = results.first

    assert record.key?("title"), "Should have title field"
    assert record.key?("description"), "Should have description field"

    assert_equal "", record["title"], "Should preserve empty string for title"
    assert_equal "", record["description"], "Should preserve empty string for description"
  end

  # Test that zero values are preserved
  def test_empty_fields_preserved_zero_values
    table_id = "tbl_zero_test"
    structure = {
      "structure" => [
        { "slug" => "priority", "label" => "Priority", "field_type" => "numberfield" },
        { "slug" => "count", "label" => "Count", "field_type" => "numberfield" }
      ]
    }
    records = [
      { "id" => "rec_1", "priority" => 0, "count" => 0 }
    ]
    @cache.cache_table_records(table_id, structure, records)

    results = @cache.query(table_id).execute
    record = results.first

    assert record.key?("priority"), "Should have priority field"
    assert record.key?("count"), "Should have count field"

    assert_equal 0, record["priority"], "Should preserve zero for priority"
    assert_equal 0, record["count"], "Should preserve zero for count"
  end

  # Test mixed empty and non-empty values
  def test_empty_fields_preserved_mixed_values
    table_id = "tbl_mixed_test"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "description", "label" => "Description", "field_type" => "textarea" },
        { "slug" => "priority", "label" => "Priority", "field_type" => "numberfield" }
      ]
    }
    records = [
      { "id" => "rec_1", "title" => "Has title", "description" => nil, "priority" => 0 },
      { "id" => "rec_2", "title" => "", "description" => "Has description", "priority" => nil }
    ]
    @cache.cache_table_records(table_id, structure, records)

    results = @cache.query(table_id).execute
    assert_equal 2, results.size

    # Check first record
    rec1 = results.find { |r| r["id"] == "rec_1" }
    assert_equal "Has title", rec1["title"]
    assert_nil rec1["description"]
    assert_equal 0, rec1["priority"]

    # Check second record
    rec2 = results.find { |r| r["id"] == "rec_2" }
    assert_equal "", rec2["title"]
    assert_equal "Has description", rec2["description"]
    assert_nil rec2["priority"]
  end

  # Test has_any_of operator (for JSON arrays)
  def test_where_has_any_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema("tbl_test_123")["sql_table_name"]
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ "rec_tags", "Tagged Task", "active", 1, '["urgent", "bug"]', Time.now.to_i, Time.now.to_i + 3600 ]
    )

    query = @cache.query("tbl_test_123")
                  .where(tags: { has_any_of: [ "urgent" ] })

    results = query.execute

    assert results.any? { |r| r["id"] == "rec_tags" }, "Should find record with tag"
  end

  # Test has_all_of operator (for JSON arrays)
  def test_where_has_all_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema("tbl_test_123")["sql_table_name"]
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ "rec_multi_tags", "Multi Tagged", "active", 1, '["urgent", "bug", "feature"]',
       Time.now.to_i, Time.now.to_i + 3600 ]
    )

    query = @cache.query("tbl_test_123")
                  .where(tags: { has_all_of: %w[urgent bug] })

    results = query.execute

    assert results.any? { |r| r["id"] == "rec_multi_tags" }, "Should find record with all tags"
  end

  # Test has_none_of operator (for JSON arrays)
  def test_where_has_none_of
    # Insert a record with JSON array field (tags)
    sql_table_name = @cache.get_cached_table_schema("tbl_test_123")["sql_table_name"]
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, name, status, priority, tags, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ "rec_clean", "Clean Task", "active", 1, '["normal"]', Time.now.to_i, Time.now.to_i + 3600 ]
    )

    query = @cache.query("tbl_test_123")
                  .where(tags: { has_none_of: %w[urgent bug] })

    results = query.execute

    assert results.any? { |r| r["id"] == "rec_clean" }, "Should find record without specified tags"
  end

  # ============================================================================
  # REGRESSION TESTS: Date Field Operators (duedatefield/daterangefield)
  # ============================================================================
  # Critical fix: Cache was using from_date but API uses to_date for comparisons
  # This ensures date filtering matches SmartSuite API behavior

  def test_daterangefield_uses_to_date_for_filtering
    # Create table with daterangefield
    table_id = "tbl_date_test"
    structure = {
      "name" => "Date Test Table",
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "project_dates", "label" => "Project Dates", "field_type" => "daterangefield" }
      ]
    }

    # Create cache table (creates project_dates_from and project_dates_to columns)
    sql_table_name = @cache.create_cache_table(table_id, structure)

    # Insert record with date range: March 1-31, 2025
    now = Time.now.to_i
    expires = now + 3600
    @cache.db.execute(
      "INSERT INTO #{sql_table_name} (id, title, project_dates_from, project_dates_to, cached_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?)",
      [ "rec_1", "March Project", "2025-03-01", "2025-03-31", now, expires ]
    )

    # Test: gte 2025-03-15 should MATCH (checks to_date: 2025-03-31 >= 2025-03-15)
    results = @cache.query(table_id)
                    .where(project_dates: { gte: "2025-03-15" })
                    .execute

    assert_equal 1, results.size, "Should find record when to_date matches filter"
    assert_equal "rec_1", results[0]["id"]

    # Test: lt 2025-03-10 should NOT match (checks to_date: 2025-03-31 < 2025-03-10 = false)
    results = @cache.query(table_id)
                    .where(project_dates: { lt: "2025-03-10" })
                    .execute

    assert_equal 0, results.size, "Should not find record when to_date does not match"
  end

  def test_duedatefield_uses_to_date_for_sorting
    # Create table with duedatefield
    table_id = "tbl_duedate_sort"
    structure = {
      "name" => "Due Date Test Table",
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "due_date", "label" => "Due Date", "field_type" => "duedatefield" }
      ]
    }

    # Create cache table (creates due_date_from and due_date_to columns)
    sql_table_name = @cache.create_cache_table(table_id, structure)

    # Insert records with different date ranges
    now = Time.now.to_i
    expires = now + 3600

    records_data = [
      [ "rec_1", "Task A", "2025-01-01", "2025-01-31" ],
      [ "rec_2", "Task B", "2025-02-01", "2025-02-15" ],
      [ "rec_3", "Task C", "2025-01-15", "2025-01-20" ]
    ]

    records_data.each do |id, title, from_date, to_date|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, title, due_date_from, due_date_to, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?)",
        [ id, title, from_date, to_date, now, expires ]
      )
    end

    # Sort by due_date ASC should use to_date column
    results = @cache.query(table_id)
                    .order("due_date", "ASC")
                    .execute

    # Expected order by to_date: Task C (01-20), Task A (01-31), Task B (02-15)
    assert_equal "rec_3", results[0]["id"], "First should be Task C (to_date: 01-20)"
    assert_equal "rec_1", results[1]["id"], "Second should be Task A (to_date: 01-31)"
    assert_equal "rec_2", results[2]["id"], "Third should be Task B (to_date: 02-15)"
  end

  # ============================================================================
  # REGRESSION TESTS: is_empty/is_not_empty for JSON Array Fields
  # ============================================================================
  # Critical fix: Cache was checking IS NULL but should check for empty array '[]'
  # Affected: userfield, multipleselectfield, linkedrecordfield

  def test_is_empty_for_json_array_fields
    # Create table with array fields
    table_id = "tbl_array_empty"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "assigned_to", "label" => "Assigned To", "field_type" => "userfield" },
        { "slug" => "tags", "label" => "Tags", "field_type" => "multipleselectfield" },
        { "slug" => "linked_records", "label" => "Linked Records", "field_type" => "linkedrecordfield" }
      ]
    }

    records = [
      { "id" => "rec_empty", "title" => "Empty", "assigned_to" => [], "tags" => [], "linked_records" => [] },
      { "id" => "rec_null", "title" => "Null", "assigned_to" => nil, "tags" => nil, "linked_records" => nil },
      { "id" => "rec_filled", "title" => "Filled", "assigned_to" => [ "user_1" ], "tags" => [ "tag_a" ],
        "linked_records" => [ "rec_1" ] }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # is_empty should match BOTH empty arrays AND null values
    results = @cache.query(table_id)
                    .where(assigned_to: { is_empty: true })
                    .execute

    assert_equal 2, results.size, "Should find both empty array and null records"
    assert results.any? { |r| r["id"] == "rec_empty" }, "Should find record with empty array"
    assert results.any? { |r| r["id"] == "rec_null" }, "Should find record with null value"

    # Test for multipleselectfield
    results = @cache.query(table_id)
                    .where(tags: { is_empty: true })
                    .execute

    assert_equal 2, results.size, "multipleselectfield: Should find both empty and null"

    # Test for linkedrecordfield
    results = @cache.query(table_id)
                    .where(linked_records: { is_empty: true })
                    .execute

    assert_equal 2, results.size, "linkedrecordfield: Should find both empty and null"
  end

  def test_is_not_empty_for_json_array_fields
    # Create table with array fields
    table_id = "tbl_array_not_empty"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "assigned_to", "label" => "Assigned To", "field_type" => "userfield" },
        { "slug" => "tags", "label" => "Tags", "field_type" => "multipleselectfield" },
        { "slug" => "linked_records", "label" => "Linked Records", "field_type" => "linkedrecordfield" }
      ]
    }

    records = [
      { "id" => "rec_empty", "title" => "Empty", "assigned_to" => [], "tags" => [], "linked_records" => [] },
      { "id" => "rec_null", "title" => "Null", "assigned_to" => nil, "tags" => nil, "linked_records" => nil },
      { "id" => "rec_filled", "title" => "Filled", "assigned_to" => [ "user_1" ], "tags" => [ "tag_a" ],
        "linked_records" => [ "rec_1" ] }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # is_not_empty should match ONLY records with actual values (not empty array, not null)
    results = @cache.query(table_id)
                    .where(assigned_to: { is_not_empty: true })
                    .execute

    assert_equal 1, results.size, "Should find only record with values"
    assert_equal "rec_filled", results[0]["id"], "Should find only filled record"

    # Test for multipleselectfield
    results = @cache.query(table_id)
                    .where(tags: { is_not_empty: true })
                    .execute

    assert_equal 1, results.size, "multipleselectfield: Should find only filled record"
    assert_equal "rec_filled", results[0]["id"]

    # Test for linkedrecordfield
    results = @cache.query(table_id)
                    .where(linked_records: { is_not_empty: true })
                    .execute

    assert_equal 1, results.size, "linkedrecordfield: Should find only filled record"
    assert_equal "rec_filled", results[0]["id"]
  end

  # ============================================================================
  # REGRESSION TESTS: is_exactly Operator for JSON Arrays
  # ============================================================================
  # New feature: Check if array contains exactly specified values (no more, no less)

  def test_is_exactly_for_multipleselectfield
    # Create table with tags
    table_id = "tbl_exactly_test"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "tags", "label" => "Tags", "field_type" => "multipleselectfield" }
      ]
    }

    records = [
      { "id" => "rec_1", "title" => "One Tag", "tags" => [ "tag_a" ] },
      { "id" => "rec_2", "title" => "Two Tags Exact", "tags" => %w[tag_a tag_b] },
      { "id" => "rec_3", "title" => "Three Tags", "tags" => %w[tag_a tag_b tag_c] },
      { "id" => "rec_4", "title" => "Two Tags Different", "tags" => %w[tag_b tag_c] },
      { "id" => "rec_5", "title" => "Empty", "tags" => [] }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # is_exactly should match ONLY records with exactly the specified tags
    results = @cache.query(table_id)
                    .where(tags: { is_exactly: %w[tag_a tag_b] })
                    .execute

    assert_equal 1, results.size, "Should find only record with exactly [tag_a, tag_b]"
    assert_equal "rec_2", results[0]["id"], "Should match Two Tags Exact"

    # Test with single value
    results = @cache.query(table_id)
                    .where(tags: { is_exactly: [ "tag_a" ] })
                    .execute

    assert_equal 1, results.size, "Should find only record with exactly [tag_a]"
    assert_equal "rec_1", results[0]["id"]

    # Test with empty array
    results = @cache.query(table_id)
                    .where(tags: { is_exactly: [] })
                    .execute

    assert_equal 1, results.size, "Should find only empty record"
    assert_equal "rec_5", results[0]["id"]
  end

  def test_is_exactly_for_linkedrecordfield
    # Create table with linked records
    table_id = "tbl_linked_exactly"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "related", "label" => "Related Records", "field_type" => "linkedrecordfield" }
      ]
    }

    records = [
      { "id" => "rec_1", "title" => "One Link", "related" => [ "link_a" ] },
      { "id" => "rec_2", "title" => "Two Links Exact", "related" => %w[link_a link_b] },
      { "id" => "rec_3", "title" => "Three Links", "related" => %w[link_a link_b link_c] }
    ]
    @cache.cache_table_records(table_id, structure, records)

    results = @cache.query(table_id)
                    .where(related: { is_exactly: %w[link_a link_b] })
                    .execute

    assert_equal 1, results.size, "linkedrecordfield: Should find exact match"
    assert_equal "rec_2", results[0]["id"]
  end

  # ============================================================================
  # REGRESSION TESTS: Field Type Detection Helpers
  # ============================================================================
  # Critical fix: Refactored regex patterns to exact type checking
  # Prevents bugs where linkedrecordfield contains "text" substring

  def test_json_array_field_detection
    # Create query instance to access helper methods
    query = @cache.query("tbl_test_123")

    # Test JSON array field types
    assert query.json_array_field?("userfield"), "Should detect userfield"
    assert query.json_array_field?("multipleselectfield"), "Should detect multipleselectfield"
    assert query.json_array_field?("linkedrecordfield"), "Should detect linkedrecordfield"

    # Test non-array field types
    refute query.json_array_field?("textfield"), "Should not detect textfield"
    refute query.json_array_field?("numberfield"), "Should not detect numberfield"
    refute query.json_array_field?("statusfield"), "Should not detect statusfield"

    # Critical: linkedrecordfield contains "field" substring but should still be detected correctly
    refute query.json_array_field?("textareafield"), "Should not match textareafield"
  end

  def test_text_field_detection
    query = @cache.query("tbl_test_123")

    # Test text field types
    assert query.text_field?("textfield"), "Should detect textfield"
    assert query.text_field?("textareafield"), "Should detect textareafield"
    assert query.text_field?("richtextareafield"), "Should detect richtextareafield"
    assert query.text_field?("emailfield"), "Should detect emailfield"
    assert query.text_field?("phonefield"), "Should detect phonefield"
    assert query.text_field?("linkfield"), "Should detect linkfield"

    # Test non-text field types
    refute query.text_field?("numberfield"), "Should not detect numberfield"
    refute query.text_field?("linkedrecordfield"), "Should not detect linkedrecordfield (critical test)"
    refute query.text_field?("userfield"), "Should not detect userfield"
  end

  # ============================================================================
  # REGRESSION TESTS: Numeric Field Operators (All Field Types)
  # ============================================================================
  # Verification: All numeric operators work for number, currency, percent, rating

  def test_numeric_operators_for_currency_field
    # Create table with currency field
    table_id = "tbl_currency_ops"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "amount", "label" => "Amount", "field_type" => "currencyfield" }
      ]
    }

    records = [
      { "id" => "rec_1", "title" => "Low", "amount" => 100.50 },
      { "id" => "rec_2", "title" => "Mid", "amount" => 500.00 },
      { "id" => "rec_3", "title" => "High", "amount" => 1000.75 }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # Test gt
    results = @cache.query(table_id).where(amount: { gt: 500 }).execute
    assert_equal 1, results.size, "gt: Should find values > 500"
    assert_equal "rec_3", results[0]["id"]

    # Test gte
    results = @cache.query(table_id).where(amount: { gte: 500 }).execute
    assert_equal 2, results.size, "gte: Should find values >= 500"

    # Test lt
    results = @cache.query(table_id).where(amount: { lt: 500 }).execute
    assert_equal 1, results.size, "lt: Should find values < 500"
    assert_equal "rec_1", results[0]["id"]

    # Test lte
    results = @cache.query(table_id).where(amount: { lte: 500 }).execute
    assert_equal 2, results.size, "lte: Should find values <= 500"

    # Test eq
    results = @cache.query(table_id).where(amount: { eq: 500 }).execute
    assert_equal 1, results.size, "eq: Should find exact value"
    assert_equal "rec_2", results[0]["id"]
  end

  def test_numeric_operators_for_percent_field
    table_id = "tbl_percent_ops"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "progress", "label" => "Progress", "field_type" => "percentfield" }
      ]
    }

    records = [
      { "id" => "rec_1", "title" => "Started", "progress" => 25 },
      { "id" => "rec_2", "title" => "Half Done", "progress" => 50 },
      { "id" => "rec_3", "title" => "Almost Done", "progress" => 90 }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # Test gte
    results = @cache.query(table_id).where(progress: { gte: 50 }).execute
    assert_equal 2, results.size, "percentfield gte: Should find >= 50"

    # Test lt
    results = @cache.query(table_id).where(progress: { lt: 50 }).execute
    assert_equal 1, results.size, "percentfield lt: Should find < 50"
  end

  def test_numeric_operators_for_rating_field
    table_id = "tbl_rating_ops"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "stars", "label" => "Stars", "field_type" => "ratingfield" }
      ]
    }

    records = [
      { "id" => "rec_1", "title" => "Poor", "stars" => 1 },
      { "id" => "rec_2", "title" => "Good", "stars" => 3 },
      { "id" => "rec_3", "title" => "Excellent", "stars" => 5 }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # Test gte
    results = @cache.query(table_id).where(stars: { gte: 3 }).execute
    assert_equal 2, results.size, "ratingfield gte: Should find >= 3 stars"

    # Test eq
    results = @cache.query(table_id).where(stars: { eq: 5 }).execute
    assert_equal 1, results.size, "ratingfield eq: Should find exactly 5 stars"
    assert_equal "rec_3", results[0]["id"]
  end

  # ============================================================================
  # REGRESSION TESTS: Daterangefield Sub-field Filtering (.to_date/.from_date)
  # ============================================================================
  # Critical fix: When filtering by sub-field (e.g., "date_field.to_date"), the query
  # should extract the base field slug for field lookup but use the full slug for
  # determining which column to use (_from or _to).

  def test_daterangefield_filter_by_to_date_subfield
    # Create table with daterangefield
    table_id = "tbl_subfield_test"
    structure = {
      "name" => "Subfield Test Table",
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "date_range", "label" => "Date Range", "field_type" => "daterangefield" }
      ]
    }

    # Create cache table (creates date_range_from and date_range_to columns)
    sql_table_name = @cache.create_cache_table(table_id, structure)

    # Insert records with different date ranges
    now = Time.now.to_i
    expires = now + 3600

    records_data = [
      [ "rec_hawaii", "Hawaii", "2025-11-10T00:00:00Z", "2025-11-19T07:00:00Z" ],
      [ "rec_nepal", "Nepal", "2025-11-15T00:00:00Z", "2025-11-19T18:15:00Z" ],
      [ "rec_other", "Other", "2025-11-01T00:00:00Z", "2025-11-15T00:00:00Z" ]
    ]

    records_data.each do |id, title, from_date, to_date|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, title, date_range_from, date_range_to, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?)",
        [ id, title, from_date, to_date, now, expires ]
      )
    end

    # Test: Filter by date_range.to_date should use the _to column
    # Filter for dates between 2025-11-19 07:00:00Z and 2025-11-19 23:59:59Z (day in UTC)
    results = @cache.query(table_id)
                    .where('date_range.to_date': { between: { min: "2025-11-19T07:00:00Z", max: "2025-11-19T23:59:59Z" } })
                    .execute

    assert_equal 2, results.size, "Should find Hawaii and Nepal records"
    ids = results.map { |r| r["id"] }
    assert_includes ids, "rec_hawaii", "Should include Hawaii"
    assert_includes ids, "rec_nepal", "Should include Nepal"
    refute_includes ids, "rec_other", "Should not include Other"
  end

  def test_daterangefield_filter_by_from_date_subfield
    # Create table with daterangefield
    table_id = "tbl_from_subfield"
    structure = {
      "name" => "From Subfield Test",
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "project_dates", "label" => "Project Dates", "field_type" => "daterangefield" }
      ]
    }

    sql_table_name = @cache.create_cache_table(table_id, structure)

    now = Time.now.to_i
    expires = now + 3600

    records_data = [
      [ "rec_1", "Project A", "2025-01-01T00:00:00Z", "2025-01-31T00:00:00Z" ],
      [ "rec_2", "Project B", "2025-02-01T00:00:00Z", "2025-02-28T00:00:00Z" ],
      [ "rec_3", "Project C", "2025-01-15T00:00:00Z", "2025-02-15T00:00:00Z" ]
    ]

    records_data.each do |id, title, from_date, to_date|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, title, project_dates_from, project_dates_to, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?)",
        [ id, title, from_date, to_date, now, expires ]
      )
    end

    # Test: Filter by project_dates.from_date should use the _from column
    results = @cache.query(table_id)
                    .where('project_dates.from_date': { gte: "2025-01-15T00:00:00Z" })
                    .execute

    assert_equal 2, results.size, "Should find Projects B and C"
    ids = results.map { |r| r["id"] }
    assert_includes ids, "rec_2", "Should include Project B (from: 2025-02-01)"
    assert_includes ids, "rec_3", "Should include Project C (from: 2025-01-15)"
    refute_includes ids, "rec_1", "Should not include Project A (from: 2025-01-01)"
  end

  def test_daterangefield_default_uses_to_date
    # Verify that without sub-field suffix, default is to use _to column
    table_id = "tbl_default_to"
    structure = {
      "name" => "Default To Test",
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "dates", "label" => "Dates", "field_type" => "daterangefield" }
      ]
    }

    sql_table_name = @cache.create_cache_table(table_id, structure)

    now = Time.now.to_i
    expires = now + 3600

    records_data = [
      [ "rec_1", "Range A", "2025-01-01T00:00:00Z", "2025-01-15T00:00:00Z" ],
      [ "rec_2", "Range B", "2025-01-10T00:00:00Z", "2025-01-25T00:00:00Z" ]
    ]

    records_data.each do |id, title, from_date, to_date|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, title, dates_from, dates_to, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?)",
        [ id, title, from_date, to_date, now, expires ]
      )
    end

    # Filter without sub-field suffix should use _to column by default
    results = @cache.query(table_id)
                    .where(dates: { gte: "2025-01-20T00:00:00Z" })
                    .execute

    # Only Range B has to_date >= 2025-01-20
    assert_equal 1, results.size, "Should find only Range B"
    assert_equal "rec_2", results[0]["id"]
  end

  # Regression test for bug where get_record returned wrong record
  # Bug: Query.where() didn't handle built-in 'id' field, so WHERE clause was never added
  # Result: get_record() returned first cached record instead of requested record
  def test_where_filters_by_id_field
    table_id = "tbl_id_filter_test"
    structure = {
      "structure" => [
        { "slug" => "title", "label" => "Title", "field_type" => "textfield" },
        { "slug" => "status", "label" => "Status", "field_type" => "statusfield" }
      ]
    }

    # Create records with specific IDs
    # Note: statusfield stores as { 'value' => '...', 'updated_on' => '...' }
    records = [
      { "id" => "68f2c7d5c60a17bb05524112", "title" => "Presentación de Comité de TI",
        "status" => { "value" => "active", "updated_on" => "2024-01-01T00:00:00Z" } },
      { "id" => "6674c77f3636d0b05182235e", "title" => "RPA: CXP Output",
        "status" => { "value" => "complete", "updated_on" => "2024-01-02T00:00:00Z" } },
      { "id" => "abc123def456", "title" => "Another Session",
        "status" => { "value" => "pending", "updated_on" => "2024-01-03T00:00:00Z" } }
    ]
    @cache.cache_table_records(table_id, structure, records)

    # Test: Filter by specific ID should return only that record
    results = @cache.query(table_id).where(id: "68f2c7d5c60a17bb05524112").execute
    assert_equal 1, results.size, "Should return exactly 1 record"
    assert_equal "68f2c7d5c60a17bb05524112", results[0]["id"], "Should return correct record ID"
    assert_equal "Presentación de Comité de TI", results[0]["title"], "Should return correct record title"

    # Test: Filter by different ID
    results = @cache.query(table_id).where(id: "6674c77f3636d0b05182235e").execute
    assert_equal 1, results.size, "Should return exactly 1 record"
    assert_equal "6674c77f3636d0b05182235e", results[0]["id"], "Should return correct record ID"
    assert_equal "RPA: CXP Output", results[0]["title"], "Should return correct record title"

    # Test: Filter by non-existent ID
    results = @cache.query(table_id).where(id: "nonexistent123").execute
    assert_equal 0, results.size, "Should return no records for non-existent ID"

    # Test: Combine ID filter with other conditions
    results = @cache.query(table_id)
                    .where(id: "68f2c7d5c60a17bb05524112")
                    .where(status: "active")
                    .execute
    assert_equal 1, results.size, "Should return record matching both ID and status"
    assert_equal "Presentación de Comité de TI", results[0]["title"]
  end

  private

  # Create test table and populate with sample data
  def create_test_table_and_data
    table_id = "tbl_test_123"

    # Mock table structure
    structure = {
      "name" => "Test Table",
      "structure" => [
        { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
        { "slug" => "status", "label" => "Status", "field_type" => "statusfield" },
        { "slug" => "priority", "label" => "Priority", "field_type" => "numberfield" },
        { "slug" => "description", "label" => "Description", "field_type" => "textareafield" },
        { "slug" => "tags", "label" => "Tags", "field_type" => "multipleselectfield" }
      ]
    }

    # Create cache table
    sql_table_name = @cache.create_cache_table(table_id, structure)

    # Insert sample records
    now = Time.now.to_i
    expires = now + 3600

    sample_data = [
      [ "rec_1", "Task 1", "active", 1, "First task", "[]" ],
      [ "rec_2", "Task 2", "active", 3, "Second task", "[]" ],
      [ "rec_3", "Task 3", "pending", 2, "Third task", "[]" ],
      [ "rec_4", "Task 4", "archived", 4, "Fourth task", "[]" ],
      [ "rec_5", "Project 1", "active", 5, "Fifth task", "[]" ]
    ]

    sample_data.each do |data|
      @cache.db.execute(
        "INSERT INTO #{sql_table_name} (id, name, status, priority, description, tags, cached_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        data + [ now, expires ]
      )
    end
  end
end
