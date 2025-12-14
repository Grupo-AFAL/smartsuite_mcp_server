# frozen_string_literal: true

require_relative "test_helper"

# Integration tests for PostgreSQL filter operators
#
# These tests verify that all SmartSuite filter operators work correctly
# when executed against a real PostgreSQL database with realistic data.
#
# Run with: bundle exec ruby test/integration/postgres/test_filter_operators.rb
#
# Coverage Matrix:
# ┌─────────────────────┬────────────────────────────────────────────────────────────┐
# │ Field Type          │ Operators                                                  │
# ├─────────────────────┼────────────────────────────────────────────────────────────┤
# │ Status/SingleSelect │ is, is_not, is_empty, is_not_empty                         │
# │ Text                │ is, is_not, contains, is_empty, is_not_empty               │
# │ Number              │ is_greater_than, is_less_than, is_equal_or_greater_than,   │
# │                     │ is_equal_or_less_than, is_empty, is_not_empty              │
# │ Date/DueDate        │ is_before, is_after, is_on_or_before, is_on_or_after,      │
# │                     │ is_empty, is_not_empty                                     │
# │ MultiSelect/Tags    │ has_any_of, is_empty, is_not_empty                         │
# │ User/LinkedRecord   │ has_any_of, is_empty, is_not_empty                         │
# │ Boolean (Yes/No)    │ is, is_empty, is_not_empty                                 │
# └─────────────────────┴────────────────────────────────────────────────────────────┘
#
# Logical Operators:
# - AND (multiple conditions, all must match)
# - OR (multiple conditions, any can match)
# - Nested groups (AND of ORs, OR of ANDs)
#
class TestPostgresFilterOperators < Minitest::Test
  include PostgresIntegrationHelper

  def setup
    setup_test_data
  end

  def teardown
    clear_test_data
  end

  # ════════════════════════════════════════════════════════════════════════════
  # STATUS / SINGLE SELECT FIELD TESTS
  # Fields: status (statusfield), priority (singleselectfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_status_is_matches_nested_object_value
    # Status fields store: {"value": "in_progress", "updated_on": "..."}
    filter = build_filter(field: "status", comparison: "is", value: "in_progress")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_007"
    assert_equal 3, result_ids.size
  end

  def test_status_is_not_excludes_matching_records
    filter = build_filter(field: "status", comparison: "is_not", value: "complete")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_002"
    refute_includes result_ids, "rec_005"
    assert_equal 5, result_ids.size
  end

  def test_single_select_is
    filter = build_filter(field: "priority", comparison: "is", value: "high")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_005"
    assert_includes result_ids, "rec_007"
    assert_equal 3, result_ids.size
  end

  def test_single_select_is_not
    filter = build_filter(field: "priority", comparison: "is_not", value: "high")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002" # low
    assert_includes result_ids, "rec_004" # medium
    assert_includes result_ids, "rec_006" # low
    refute_includes result_ids, "rec_003" # nil - excluded from is_not
  end

  def test_single_select_is_empty
    # rec_003 has priority: nil
    filter = build_filter(field: "priority", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003"
    assert_equal 1, result_ids.size
  end

  def test_single_select_is_not_empty
    filter = build_filter(field: "priority", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_003"
    assert_equal 6, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # TEXT FIELD TESTS
  # Fields: title (recordtitlefield), description (textfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_text_is_exact_match
    filter = build_filter(field: "title", comparison: "is", value: "Complete Task")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_equal 1, result_ids.size
  end

  def test_text_is_not
    filter = build_filter(field: "title", comparison: "is_not", value: "Complete Task")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_001"
    assert_equal 6, result_ids.size
  end

  def test_text_contains_case_insensitive
    filter = build_filter(field: "description", comparison: "contains", value: "ENTERPRISE")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_007"
    assert_equal 1, result_ids.size
  end

  def test_text_contains_partial_match
    filter = build_filter(field: "description", comparison: "contains", value: "task")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # "complete task"
    assert_includes result_ids, "rec_002" # "Task with empty"
    assert_includes result_ids, "rec_005" # "Task with string"
  end

  def test_text_contains_unicode
    filter = build_filter(field: "description", comparison: "contains", value: "café")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_004"
  end

  def test_text_is_empty
    # rec_003 has description: nil, rec_006 has description: ""
    filter = build_filter(field: "description", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003"
    assert_includes result_ids, "rec_006"
    assert_equal 2, result_ids.size
  end

  def test_text_is_not_empty
    filter = build_filter(field: "description", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_003"
    refute_includes result_ids, "rec_006"
    assert_equal 5, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # NUMERIC FIELD TESTS
  # Fields: amount (numberfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_numeric_is_greater_than
    filter = build_filter(field: "amount", comparison: "is_greater_than", value: 1000)
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 1500.50
    assert_includes result_ids, "rec_007" # 50000
    refute_includes result_ids, "rec_002" # 250
    refute_includes result_ids, "rec_004" # 999.99
  end

  def test_numeric_is_less_than
    filter = build_filter(field: "amount", comparison: "is_less_than", value: 100)
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_005" # 0
    assert_includes result_ids, "rec_006" # 50
    refute_includes result_ids, "rec_002" # 250
  end

  def test_numeric_is_equal_or_greater_than
    filter = build_filter(field: "amount", comparison: "is_equal_or_greater_than", value: 999.99)
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 1500.50
    assert_includes result_ids, "rec_004" # 999.99 exact match
    assert_includes result_ids, "rec_007" # 50000
    refute_includes result_ids, "rec_002" # 250
  end

  def test_numeric_is_equal_or_less_than
    filter = build_filter(field: "amount", comparison: "is_equal_or_less_than", value: 250)
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002" # 250 exact match
    assert_includes result_ids, "rec_005" # 0
    assert_includes result_ids, "rec_006" # 50
    refute_includes result_ids, "rec_001" # 1500.50
  end

  def test_numeric_is_empty
    # rec_003 has amount: nil
    filter = build_filter(field: "amount", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003"
    assert_equal 1, result_ids.size
  end

  def test_numeric_is_not_empty
    filter = build_filter(field: "amount", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_003"
    assert_equal 6, result_ids.size
  end

  def test_numeric_with_decimal_precision
    # Test that 999.99 matches exactly
    filter = build_filter(field: "amount", comparison: "is_equal_or_greater_than", value: 999.99)
    result_ids = filter_record_ids(filter)
    assert_includes result_ids, "rec_004"

    filter2 = build_filter(field: "amount", comparison: "is_greater_than", value: 999.99)
    result_ids2 = filter_record_ids(filter2)
    refute_includes result_ids2, "rec_004" # 999.99 is not > 999.99
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DATE FIELD TESTS
  # Fields: due_date (duedatefield), created_date (datefield)
  # Handles both Date Range structure and simple date strings
  # ════════════════════════════════════════════════════════════════════════════

  def test_date_is_before
    filter = build_filter(
      field: "due_date",
      comparison: "is_before",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-07-01" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 2025-06-15
    assert_includes result_ids, "rec_004" # 2025-05-15
    refute_includes result_ids, "rec_002" # 2025-07-01 (not before, equal)
    refute_includes result_ids, "rec_003" # null due_date
  end

  def test_date_is_after
    filter = build_filter(
      field: "due_date",
      comparison: "is_after",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-08-01" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_005" # 2025-08-31
    assert_includes result_ids, "rec_007" # 2025-12-31
    refute_includes result_ids, "rec_001" # 2025-06-15
  end

  def test_date_is_on_or_before
    filter = build_filter(
      field: "due_date",
      comparison: "is_on_or_before",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-06-15" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 2025-06-15 exact match
    assert_includes result_ids, "rec_004" # 2025-05-15 before
    refute_includes result_ids, "rec_002" # 2025-07-01 after
  end

  def test_date_is_on_or_after
    filter = build_filter(
      field: "due_date",
      comparison: "is_on_or_after",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-08-31" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_005" # 2025-08-31 exact match
    assert_includes result_ids, "rec_007" # 2025-12-31 after
    refute_includes result_ids, "rec_001" # 2025-06-15 before
  end

  def test_date_null_excluded_from_comparisons
    # Records with null dates should never match date comparisons
    filter = build_filter(
      field: "due_date",
      comparison: "is_after",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2000-01-01" }
    )
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_003" # null due_date
    refute_includes result_ids, "rec_006" # empty object due_date
  end

  def test_date_with_string_format_to_date
    # rec_005 has due_date.to_date as string "2025-08-31" instead of nested object
    filter = build_filter(
      field: "due_date",
      comparison: "is_on_or_before",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-08-31" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_005"
  end

  def test_date_is_empty
    # rec_003 has due_date.to_date = null, rec_006 has due_date = {}
    filter = build_filter(field: "due_date", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003"
    assert_includes result_ids, "rec_006"
  end

  def test_simple_date_field
    # created_date is a simple date string, not Date Range
    filter = build_filter(
      field: "created_date",
      comparison: "is_before",
      value: { "date_mode" => "exact_date", "date_mode_value" => "2025-03-01" }
    )
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 2025-01-15
    assert_includes result_ids, "rec_002" # 2025-02-01
    refute_includes result_ids, "rec_004" # 2025-04-01
  end

  # ════════════════════════════════════════════════════════════════════════════
  # MULTI-SELECT / TAGS FIELD TESTS
  # Fields: tags (multipleselectfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_multiselect_has_any_of_single
    filter = build_filter(field: "tags", comparison: "has_any_of", value: [ "urgent" ])
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_equal 1, result_ids.size
  end

  def test_multiselect_has_any_of_multiple
    filter = build_filter(field: "tags", comparison: "has_any_of", value: [ "backend", "frontend" ])
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # has frontend
    assert_includes result_ids, "rec_005" # has backend
    assert_equal 2, result_ids.size
  end

  def test_multiselect_has_any_of_no_match
    filter = build_filter(field: "tags", comparison: "has_any_of", value: [ "nonexistent" ])
    result_ids = filter_record_ids(filter)

    assert_empty result_ids
  end

  def test_multiselect_has_any_of_empty_array
    filter = build_filter(field: "tags", comparison: "has_any_of", value: [])
    result_ids = filter_record_ids(filter)

    assert_empty result_ids, "has_any_of with empty array should match nothing"
  end

  def test_multiselect_is_empty
    # rec_002 has tags: [], rec_003 has tags: nil
    filter = build_filter(field: "tags", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002"
    assert_includes result_ids, "rec_003"
  end

  def test_multiselect_is_not_empty
    filter = build_filter(field: "tags", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_002"
    refute_includes result_ids, "rec_003"
    assert_equal 5, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # USER FIELD TESTS
  # Fields: assigned_to (userfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_user_has_any_of_single
    filter = build_filter(field: "assigned_to", comparison: "has_any_of", value: [ "user_001" ])
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_007"
  end

  def test_user_has_any_of_multiple
    filter = build_filter(field: "assigned_to", comparison: "has_any_of", value: [ "user_002", "user_003" ])
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # has user_002
    assert_includes result_ids, "rec_005" # has user_003
    assert_includes result_ids, "rec_007" # has both
  end

  def test_user_is_empty
    # rec_002 has assigned_to: [], rec_003 has assigned_to: nil, rec_006 has assigned_to: {}
    filter = build_filter(field: "assigned_to", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002"
    assert_includes result_ids, "rec_003"
    assert_includes result_ids, "rec_006"
  end

  def test_user_is_not_empty
    filter = build_filter(field: "assigned_to", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_005"
    assert_includes result_ids, "rec_007"
    assert_equal 4, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # LINKED RECORD FIELD TESTS
  # Fields: linked_records (linkedrecordfield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_linked_record_has_any_of
    filter = build_filter(field: "linked_records", comparison: "has_any_of", value: [ "rec_other_001" ])
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_007"
  end

  def test_linked_record_is_empty
    # rec_002, rec_003, rec_005 have empty/null, rec_006 has {}
    filter = build_filter(field: "linked_records", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002"
    assert_includes result_ids, "rec_003"
    assert_includes result_ids, "rec_005"
    assert_includes result_ids, "rec_006"
  end

  def test_linked_record_is_not_empty
    filter = build_filter(field: "linked_records", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_007"
    assert_equal 3, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # BOOLEAN (YES/NO) FIELD TESTS
  # Fields: is_active (yesnofield)
  # ════════════════════════════════════════════════════════════════════════════

  def test_boolean_is_true
    filter = build_filter(field: "is_active", comparison: "is", value: "true")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_005"
    assert_includes result_ids, "rec_007"
  end

  def test_boolean_is_false
    filter = build_filter(field: "is_active", comparison: "is", value: "false")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002"
    assert_includes result_ids, "rec_006"
  end

  def test_boolean_is_empty
    # rec_003 has is_active: nil
    filter = build_filter(field: "is_active", comparison: "is_empty")
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003"
    assert_equal 1, result_ids.size
  end

  def test_boolean_is_not_empty
    filter = build_filter(field: "is_active", comparison: "is_not_empty")
    result_ids = filter_record_ids(filter)

    refute_includes result_ids, "rec_003"
    assert_equal 6, result_ids.size
  end

  # ════════════════════════════════════════════════════════════════════════════
  # COMBINED FILTERS - AND LOGIC
  # ════════════════════════════════════════════════════════════════════════════

  def test_and_two_conditions
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "in_progress" },
        { "field" => "priority", "comparison" => "is", "value" => "high" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_007"
    refute_includes result_ids, "rec_004" # in_progress but medium
    assert_equal 2, result_ids.size
  end

  def test_and_three_conditions
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "in_progress" },
        { "field" => "priority", "comparison" => "is", "value" => "high" },
        { "field" => "amount", "comparison" => "is_greater_than", "value" => 1000 }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 1500.50
    assert_includes result_ids, "rec_007" # 50000
    assert_equal 2, result_ids.size
  end

  def test_and_with_date_and_numeric
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "due_date", "comparison" => "is_before",
          "value" => { "date_mode" => "exact_date", "date_mode_value" => "2025-08-01" } },
        { "field" => "amount", "comparison" => "is_greater_than", "value" => 1000 }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # due 2025-06-15, amount 1500.50
    refute_includes result_ids, "rec_007" # due 2025-12-31 (after 2025-08-01)
  end

  def test_and_with_is_not_empty
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "linked_records", "comparison" => "is_not_empty" },
        { "field" => "status", "comparison" => "is", "value" => "in_progress" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001"
    assert_includes result_ids, "rec_004"
    assert_includes result_ids, "rec_007"
    refute_includes result_ids, "rec_002" # linked_records empty
    refute_includes result_ids, "rec_005" # status is complete
  end

  def test_and_with_has_any_of
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "tags", "comparison" => "has_any_of", "value" => [ "urgent", "priority" ] },
        { "field" => "amount", "comparison" => "is_greater_than", "value" => 100 }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # urgent, 1500.50
    assert_includes result_ids, "rec_007" # priority, 50000
  end

  # ════════════════════════════════════════════════════════════════════════════
  # COMBINED FILTERS - OR LOGIC
  # ════════════════════════════════════════════════════════════════════════════

  def test_or_two_conditions
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "complete" },
        { "field" => "priority", "comparison" => "is", "value" => "low" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002" # complete OR low (both)
    assert_includes result_ids, "rec_005" # complete
    assert_includes result_ids, "rec_006" # low
    refute_includes result_ids, "rec_001" # in_progress, high
    refute_includes result_ids, "rec_004" # in_progress, medium
  end

  def test_or_three_conditions
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "priority", "comparison" => "is", "value" => "high" },
        { "field" => "priority", "comparison" => "is", "value" => "medium" },
        { "field" => "priority", "comparison" => "is", "value" => "low" }
      ]
    }
    result_ids = filter_record_ids(filter)

    # All records with any priority (excludes rec_003 with nil priority)
    assert_equal 6, result_ids.size
    refute_includes result_ids, "rec_003"
  end

  def test_or_with_different_field_types
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "amount", "comparison" => "is_greater_than", "value" => 10000 },
        { "field" => "tags", "comparison" => "has_any_of", "value" => [ "urgent" ] }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # urgent tag
    assert_includes result_ids, "rec_007" # amount 50000
    assert_equal 2, result_ids.size
  end

  def test_or_with_is_empty
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "description", "comparison" => "is_empty" },
        { "field" => "priority", "comparison" => "is_empty" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_003" # both empty
    assert_includes result_ids, "rec_006" # description empty
  end

  # ════════════════════════════════════════════════════════════════════════════
  # COMPLEX NESTED FILTERS
  # ════════════════════════════════════════════════════════════════════════════

  def test_and_with_multiple_same_field
    # Find records where amount is between 200 and 2000
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "amount", "comparison" => "is_greater_than", "value" => 200 },
        { "field" => "amount", "comparison" => "is_less_than", "value" => 2000 }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # 1500.50
    assert_includes result_ids, "rec_002" # 250
    assert_includes result_ids, "rec_004" # 999.99
    refute_includes result_ids, "rec_005" # 0
    refute_includes result_ids, "rec_007" # 50000
  end

  def test_complex_business_scenario
    # Find high-priority in-progress tasks with linked records due before Q4
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "in_progress" },
        { "field" => "priority", "comparison" => "is", "value" => "high" },
        { "field" => "linked_records", "comparison" => "is_not_empty" },
        { "field" => "due_date", "comparison" => "is_before",
          "value" => { "date_mode" => "exact_date", "date_mode_value" => "2025-10-01" } }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # Matches all conditions
    refute_includes result_ids, "rec_007" # Due 2025-12-31 (Q4)
  end

  def test_or_with_is_empty_and_specific_value
    # Find records that either have no priority OR are high priority
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "priority", "comparison" => "is_empty" },
        { "field" => "priority", "comparison" => "is", "value" => "high" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_001" # high
    assert_includes result_ids, "rec_003" # nil
    assert_includes result_ids, "rec_005" # high
    assert_includes result_ids, "rec_007" # high
    refute_includes result_ids, "rec_002" # low
    refute_includes result_ids, "rec_004" # medium
  end

  # ════════════════════════════════════════════════════════════════════════════
  # EDGE CASES
  # ════════════════════════════════════════════════════════════════════════════

  def test_filter_with_no_matches
    filter = build_filter(field: "status", comparison: "is", value: "nonexistent_status")
    result_ids = filter_record_ids(filter)

    assert_empty result_ids
  end

  def test_empty_fields_array
    filter = { "operator" => "and", "fields" => [] }
    records = @cache.get_cached_records(@table_id, filter: filter)

    # Empty filter should return all records
    assert_equal 7, records.size
  end

  def test_single_field_filter_with_and
    # Single condition in AND should still work
    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "complete" }
      ]
    }
    result_ids = filter_record_ids(filter)

    assert_includes result_ids, "rec_002"
    assert_includes result_ids, "rec_005"
    assert_equal 2, result_ids.size
  end

  def test_filter_nil_value_in_is
    # Filtering with nil value should match nothing (use is_empty instead)
    filter = build_filter(field: "priority", comparison: "is", value: nil)
    result_ids = filter_record_ids(filter)

    # nil.to_s = "" so this matches empty strings, not null values
    # This is expected behavior - use is_empty for null checks
    assert_equal 0, result_ids.size
  end
end
