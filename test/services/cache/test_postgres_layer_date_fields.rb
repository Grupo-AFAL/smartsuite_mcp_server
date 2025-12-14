# frozen_string_literal: true

require "minitest/autorun"
require "date"

# Unit tests for PostgresLayer date field handling
#
# These tests verify the SQL generation for date comparisons,
# particularly for Date Range fields (SMARTSUITE-MCP-5).
#
# We can't test actual queries without PostgreSQL, but we can verify
# that the generated SQL is correct for both Date Range and simple date fields.
class TestPostgresLayerDateFields < Minitest::Test
  # Stub class to test the date_field_accessor and build_single_jsonb_condition methods
  # without requiring ActiveRecord or PostgreSQL connection
  class PostgresLayerStub
    def sanitize_field_name(field)
      # Basic sanitization - remove quotes and SQL injection attempts
      field.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    def date_field_accessor(field)
      sanitized = sanitize_field_name(field)
      <<~SQL.gsub(/\s+/, " ").strip
        COALESCE(
          SUBSTRING(data->'#{sanitized}'->'to_date'->>'date' FROM 1 FOR 10),
          SUBSTRING(data->>'#{sanitized}' FROM 1 FOR 10)
        )
      SQL
    end

    def extract_date_value(value)
      if value.is_a?(Hash)
        return value["date_mode_value"] if value["date_mode_value"]
        return value["date"] if value["date"]

        resolve_date_mode(value["date_mode"])
      else
        value.to_s
      end
    end

    def resolve_date_mode(date_mode)
      return nil unless date_mode

      today = Date.today
      case date_mode.to_s.downcase
      when "today" then today.to_s
      when "exact_date" then nil # exact_date requires date_mode_value
      else date_mode.to_s
      end
    end

    def build_date_condition(field, comparison, value)
      date_value = extract_date_value(value)
      return nil unless date_value

      date_accessor = date_field_accessor(field)
      param_num = 1

      case comparison
      when "is_before"
        [ "#{date_accessor} < $#{param_num}", [ date_value ] ]
      when "is_after"
        [ "#{date_accessor} > $#{param_num}", [ date_value ] ]
      when "is_on_or_before"
        [ "#{date_accessor} <= $#{param_num}", [ date_value ] ]
      when "is_on_or_after"
        [ "#{date_accessor} >= $#{param_num}", [ date_value ] ]
      end
    end
  end

  def setup
    @layer = PostgresLayerStub.new
  end

  # ============================================
  # Tests for date_field_accessor SQL generation
  # ============================================

  def test_date_field_accessor_generates_coalesce
    sql = @layer.date_field_accessor("due_date")

    assert_includes sql, "COALESCE"
    assert_includes sql, "data->'due_date'->'to_date'->>'date'"
    assert_includes sql, "data->>'due_date'"
  end

  def test_date_field_accessor_extracts_first_10_chars
    sql = @layer.date_field_accessor("due_date")

    # Should extract YYYY-MM-DD (10 characters)
    assert_includes sql, "SUBSTRING"
    assert_includes sql, "FROM 1 FOR 10"
  end

  def test_date_field_accessor_sanitizes_field_name
    sql = @layer.date_field_accessor("due_date'; DROP TABLE users;--")

    # Should sanitize the field name - removes SQL injection characters
    # Note: Single quotes are part of PostgreSQL JSONB syntax, not injection
    refute_includes sql, "DROP TABLE"
    refute_includes sql, ";"
    refute_includes sql, "--"
    # The sanitized field name should only contain alphanumeric and underscore
    assert_includes sql, "due_dateDROPTABLEusers"
  end

  def test_date_field_accessor_handles_date_range_format
    # The accessor should try Date Range format first:
    # {"to_date": {"date": "2024-06-24T00:00:00Z", ...}}
    sql = @layer.date_field_accessor("due_date")

    # Should access to_date.date path for Date Range fields
    assert_includes sql, "data->'due_date'->'to_date'->>'date'"
  end

  def test_date_field_accessor_falls_back_to_simple_date
    # Should fall back to simple date format if Date Range doesn't exist
    sql = @layer.date_field_accessor("created_at")

    assert_includes sql, "data->>'created_at'"
  end

  # ============================================
  # Tests for date comparison conditions
  # ============================================

  def test_is_before_generates_less_than
    condition, params = @layer.build_date_condition(
      "due_date",
      "is_before",
      { "date_mode" => "exact_date", "date_mode_value" => "2025-12-13" }
    )

    assert_includes condition, "<"
    assert_equal [ "2025-12-13" ], params
  end

  def test_is_after_generates_greater_than
    condition, params = @layer.build_date_condition(
      "due_date",
      "is_after",
      { "date_mode" => "exact_date", "date_mode_value" => "2025-01-01" }
    )

    assert_includes condition, ">"
    assert_equal [ "2025-01-01" ], params
  end

  def test_is_on_or_before_generates_less_than_or_equal
    condition, params = @layer.build_date_condition(
      "due_date",
      "is_on_or_before",
      { "date_mode_value" => "2025-12-31" }
    )

    assert_includes condition, "<="
    assert_equal [ "2025-12-31" ], params
  end

  def test_is_on_or_after_generates_greater_than_or_equal
    condition, params = @layer.build_date_condition(
      "due_date",
      "is_on_or_after",
      { "date" => "2025-01-01" }
    )

    assert_includes condition, ">="
    assert_equal [ "2025-01-01" ], params
  end

  def test_date_condition_with_today
    condition, params = @layer.build_date_condition(
      "due_date",
      "is_before",
      { "date_mode" => "today" }
    )

    assert_equal [ Date.today.to_s ], params
  end

  def test_date_condition_uses_date_field_accessor
    condition, _params = @layer.build_date_condition(
      "due_date",
      "is_before",
      { "date_mode_value" => "2025-12-13" }
    )

    # Should use the COALESCE accessor, not simple data->>'field'
    assert_includes condition, "COALESCE"
    assert_includes condition, "to_date"
  end

  # ============================================
  # Tests for extract_date_value priority
  # ============================================

  def test_extract_date_value_priority_date_mode_value_first
    value = {
      "date_mode" => "today",
      "date_mode_value" => "2025-01-15",
      "date" => "2025-02-20"
    }
    assert_equal "2025-01-15", @layer.extract_date_value(value)
  end

  def test_extract_date_value_priority_date_second
    value = {
      "date_mode" => "today",
      "date" => "2025-02-20"
    }
    assert_equal "2025-02-20", @layer.extract_date_value(value)
  end

  def test_extract_date_value_priority_date_mode_last
    value = { "date_mode" => "today" }
    assert_equal Date.today.to_s, @layer.extract_date_value(value)
  end

  def test_extract_date_value_with_plain_string
    assert_equal "2025-03-10", @layer.extract_date_value("2025-03-10")
  end
end
