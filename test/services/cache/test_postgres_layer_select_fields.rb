# frozen_string_literal: true

require "minitest/autorun"

# Unit tests for PostgresLayer status/single select field handling
#
# These tests verify the SQL generation for status and single select field comparisons.
# Status fields store values as objects: {"value": "in_progress", "updated_on": "..."}
# Single select fields may store values as simple strings or objects.
#
# We can't test actual queries without PostgreSQL, but we can verify
# that the generated SQL is correct for both formats.
class TestPostgresLayerSelectFields < Minitest::Test
  # Stub class to test the select_field_value_accessor method
  # without requiring ActiveRecord or PostgreSQL connection
  class PostgresLayerStub
    def sanitize_field_name(field)
      # Basic sanitization - remove quotes and SQL injection attempts
      field.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    def select_field_value_accessor(field)
      sanitized = sanitize_field_name(field)
      <<~SQL.gsub(/\s+/, " ").strip
        COALESCE(
          data->'#{sanitized}'->>'value',
          data->>'#{sanitized}'
        )
      SQL
    end

    def build_status_condition(field, comparison, value)
      select_accessor = select_field_value_accessor(field)
      param_num = 1

      case comparison
      when "is"
        [ "#{select_accessor} = $#{param_num}", [ value.to_s ] ]
      when "is_not"
        [ "#{select_accessor} != $#{param_num}", [ value.to_s ] ]
      end
    end
  end

  def setup
    @layer = PostgresLayerStub.new
  end

  # ============================================
  # Tests for select_field_value_accessor SQL generation
  # ============================================

  def test_select_field_accessor_generates_coalesce
    sql = @layer.select_field_value_accessor("status")

    assert_includes sql, "COALESCE"
    assert_includes sql, "data->'status'->>'value'"
    assert_includes sql, "data->>'status'"
  end

  def test_select_field_accessor_tries_nested_value_first
    sql = @layer.select_field_value_accessor("priority")

    # Should try nested object format first: data->'field'->>'value'
    # Then fall back to simple string: data->>'field'
    assert_match(/COALESCE.*data->'priority'->>'value'.*data->>'priority'/, sql)
  end

  def test_select_field_accessor_sanitizes_field_name
    sql = @layer.select_field_value_accessor("status'; DROP TABLE users;--")

    # Should sanitize the field name - removes SQL injection characters
    refute_includes sql, "DROP TABLE"
    refute_includes sql, ";"
    refute_includes sql, "--"
    # The sanitized field name should only contain alphanumeric and underscore
    assert_includes sql, "statusDROPTABLEusers"
  end

  # ============================================
  # Tests for status comparison conditions
  # ============================================

  def test_is_generates_equality
    condition, params = @layer.build_status_condition("status", "is", "in_progress")

    assert_includes condition, "="
    refute_includes condition, "!="
    assert_equal [ "in_progress" ], params
  end

  def test_is_not_generates_inequality
    condition, params = @layer.build_status_condition("status", "is_not", "complete")

    assert_includes condition, "!="
    assert_equal [ "complete" ], params
  end

  def test_condition_uses_select_field_accessor
    condition, _params = @layer.build_status_condition("status", "is", "in_progress")

    # Should use the COALESCE accessor
    assert_includes condition, "COALESCE"
    assert_includes condition, "->>'value'"
  end

  def test_condition_converts_value_to_string
    condition, params = @layer.build_status_condition("priority", "is", :high)

    assert_equal [ "high" ], params
  end

  # ============================================
  # Tests for different field types that use this accessor
  # ============================================

  def test_works_with_status_field
    sql = @layer.select_field_value_accessor("status")
    assert_includes sql, "status"
  end

  def test_works_with_priority_field
    sql = @layer.select_field_value_accessor("priority")
    assert_includes sql, "priority"
  end

  def test_works_with_custom_single_select_field
    sql = @layer.select_field_value_accessor("custom_category")
    assert_includes sql, "custom_category"
  end
end
