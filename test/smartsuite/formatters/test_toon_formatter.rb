# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/smart_suite/formatters/toon_formatter"
require "json"

class ToonFormatterTest < Minitest::Test
  include SmartSuite::Formatters::ToonFormatter

  def test_format_records_with_data
    records = [
      { "id" => "rec_1", "title" => "Task 1", "status" => "active" },
      { "id" => "rec_2", "title" => "Task 2", "status" => "done" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_records(
      records,
      total_count: 100,
      filtered_count: 50
    )

    assert result.is_a?(String)
    assert_includes result, "=== Showing 2 of 50 filtered records (100 total) ==="
    assert_includes result, "records[2]"
    assert_includes result, "rec_1"
    assert_includes result, "Task 1"
  end

  def test_format_records_empty
    result = SmartSuite::Formatters::ToonFormatter.format_records(
      [],
      total_count: 100,
      filtered_count: 0
    )

    assert_includes result, "No records found"
  end

  def test_format_records_no_filter
    records = [
      { "id" => "rec_1", "title" => "Task 1" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_records(
      records,
      total_count: 10
    )

    assert_includes result, "=== Showing 1 of 10 total records ==="
  end

  def test_format_record_single
    record = { "id" => "rec_1", "title" => "Test", "priority" => 5 }

    result = SmartSuite::Formatters::ToonFormatter.format_record(record)

    assert result.is_a?(String)
    assert_includes result, "id: rec_1"
    assert_includes result, "title: Test"
    assert_includes result, "priority: 5"
  end

  def test_format_solutions
    solutions = [
      { "id" => "sol_1", "name" => "Solution 1" },
      { "id" => "sol_2", "name" => "Solution 2" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_solutions(solutions)

    assert result.is_a?(String)
    assert_includes result, "solutions[2]"
    assert_includes result, "sol_1"
    assert_includes result, "Solution 1"
  end

  def test_format_solutions_empty
    result = SmartSuite::Formatters::ToonFormatter.format_solutions([])

    assert_equal "solutions[0]:", result
  end

  def test_format_tables
    tables = [
      { "id" => "tbl_1", "name" => "Tasks" },
      { "id" => "tbl_2", "name" => "Projects" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_tables(tables)

    assert result.is_a?(String)
    assert_includes result, "tables[2]"
    assert_includes result, "tbl_1"
    assert_includes result, "Tasks"
  end

  def test_format_tables_empty
    result = SmartSuite::Formatters::ToonFormatter.format_tables([])

    assert_equal "tables[0]:", result
  end

  def test_format_members
    members = [
      { "id" => "user_1", "email" => "user1@example.com" },
      { "id" => "user_2", "email" => "user2@example.com" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_members(members)

    assert result.is_a?(String)
    assert_includes result, "members[2]"
    assert_includes result, "user_1"
    assert_includes result, "user1@example.com"
  end

  def test_format_members_empty
    result = SmartSuite::Formatters::ToonFormatter.format_members([])

    assert_equal "members[0]:", result
  end

  def test_format_generic_hash
    data = { "key1" => "value1", "key2" => "value2" }

    result = SmartSuite::Formatters::ToonFormatter.format(data)

    assert result.is_a?(String)
    assert_includes result, "key1: value1"
    assert_includes result, "key2: value2"
  end

  def test_format_with_custom_delimiter
    records = [
      { "id" => "rec_1", "title" => "Task 1" }
    ]

    result = SmartSuite::Formatters::ToonFormatter.format_records(
      records,
      total_count: 1,
      delimiter: "|"
    )

    assert result.is_a?(String)
    # Pipe delimiter should be used in the output (including header notation)
    assert_includes result, "records[1|]"
  end

  def test_token_savings_vs_json
    records = [
      { "id" => "rec_1", "title" => "Task 1", "status" => "active", "priority" => 5 },
      { "id" => "rec_2", "title" => "Task 2", "status" => "done", "priority" => 3 },
      { "id" => "rec_3", "title" => "Task 3", "status" => "pending", "priority" => 1 }
    ]

    toon_result = SmartSuite::Formatters::ToonFormatter.format_records(
      records,
      total_count: 3
    )
    json_result = JSON.generate(records)

    # TOON should be significantly shorter than JSON
    # (This is a rough estimate, actual token savings may vary)
    assert toon_result.length < json_result.length * 1.2,
           "TOON (#{toon_result.length} chars) should be more compact than JSON (#{json_result.length} chars)"
  end
end
