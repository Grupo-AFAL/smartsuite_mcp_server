# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/smart_suite/filter_validator"

class TestFilterValidator < Minitest::Test
  # ============================================================================
  # operators_for_field_type Tests
  # ============================================================================

  def test_operators_for_text_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("textfield")

    assert_includes operators, "is"
    assert_includes operators, "is_not"
    assert_includes operators, "contains"
    assert_includes operators, "not_contains"
    assert_includes operators, "is_empty"
    assert_includes operators, "is_not_empty"
    refute_includes operators, "is_greater_than"
    refute_includes operators, "has_any_of"
  end

  def test_operators_for_numeric_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("numberfield")

    assert_includes operators, "is"
    assert_includes operators, "is_not"
    assert_includes operators, "is_greater_than"
    assert_includes operators, "is_less_than"
    assert_includes operators, "is_equal_or_greater_than"
    assert_includes operators, "is_equal_or_less_than"
    assert_includes operators, "is_empty"
    refute_includes operators, "contains"
    refute_includes operators, "has_any_of"
  end

  def test_operators_for_autonumber_fields_no_empty
    operators = SmartSuite::FilterValidator.operators_for_field_type("autonumberfield")

    assert_includes operators, "is"
    assert_includes operators, "is_greater_than"
    # Auto number doesn't support empty checks
    refute_includes operators, "is_empty"
    refute_includes operators, "is_not_empty"
  end

  def test_operators_for_date_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("datefield")

    assert_includes operators, "is"
    assert_includes operators, "is_not"
    assert_includes operators, "is_before"
    assert_includes operators, "is_on_or_before"
    assert_includes operators, "is_on_or_after"
    assert_includes operators, "is_empty"
    refute_includes operators, "is_overdue" # Only due date
    refute_includes operators, "contains"
  end

  def test_operators_for_duedate_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("duedatefield")

    # Regular date operators
    assert_includes operators, "is"
    assert_includes operators, "is_before"
    # Special due date operators
    assert_includes operators, "is_overdue"
    assert_includes operators, "is_not_overdue"
  end

  def test_operators_for_single_select_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("statusfield")

    assert_includes operators, "is"
    assert_includes operators, "is_not"
    assert_includes operators, "is_any_of"
    assert_includes operators, "is_none_of"
    assert_includes operators, "is_empty"
    refute_includes operators, "has_any_of" # That's for multiple select
    refute_includes operators, "contains"
  end

  def test_operators_for_multiple_select_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("multipleselectfield")

    assert_includes operators, "has_any_of"
    assert_includes operators, "has_all_of"
    assert_includes operators, "is_exactly"
    assert_includes operators, "has_none_of"
    assert_includes operators, "is_empty"
    refute_includes operators, "is" # NOT valid for multiple select
    refute_includes operators, "is_any_of" # That's for single select
  end

  def test_operators_for_linked_record_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("linkedrecordfield")

    assert_includes operators, "has_any_of"
    assert_includes operators, "has_all_of"
    assert_includes operators, "contains"
    assert_includes operators, "not_contains"
    assert_includes operators, "is_empty"
    refute_includes operators, "is" # NOT valid for linked records
  end

  def test_operators_for_user_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("assignedtofield")

    assert_includes operators, "has_any_of"
    assert_includes operators, "has_all_of"
    assert_includes operators, "is_exactly"
    assert_includes operators, "is_empty"
    refute_includes operators, "is" # NOT valid for user fields
    refute_includes operators, "contains"
  end

  def test_operators_for_file_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("filefield")

    assert_includes operators, "file_name_contains"
    assert_includes operators, "file_type_is"
    assert_includes operators, "is_empty"
    assert_includes operators, "is_not_empty"
    refute_includes operators, "contains"
    refute_includes operators, "is"
  end

  def test_operators_for_yesno_fields
    operators = SmartSuite::FilterValidator.operators_for_field_type("yesnofield")

    assert_includes operators, "is"
    refute_includes operators, "is_not"
    refute_includes operators, "contains"
    refute_includes operators, "is_greater_than"
  end

  def test_operators_for_formula_fields_returns_nil
    # Formula fields inherit from return type, can't validate
    operators = SmartSuite::FilterValidator.operators_for_field_type("formulafield")
    assert_nil operators

    operators = SmartSuite::FilterValidator.operators_for_field_type("lookupfield")
    assert_nil operators

    operators = SmartSuite::FilterValidator.operators_for_field_type("rollupfield")
    assert_nil operators
  end

  def test_operators_for_unknown_field_type_returns_nil
    operators = SmartSuite::FilterValidator.operators_for_field_type("unknownfield")
    assert_nil operators
  end

  # ============================================================================
  # valid? Tests
  # ============================================================================

  def test_valid_returns_true_for_valid_combination
    assert SmartSuite::FilterValidator.valid?("is", "textfield")
    assert SmartSuite::FilterValidator.valid?("contains", "textfield")
    assert SmartSuite::FilterValidator.valid?("is_greater_than", "numberfield")
    assert SmartSuite::FilterValidator.valid?("has_any_of", "multipleselectfield")
  end

  def test_valid_returns_false_for_invalid_combination
    refute SmartSuite::FilterValidator.valid?("contains", "numberfield")
    refute SmartSuite::FilterValidator.valid?("is_greater_than", "textfield")
    refute SmartSuite::FilterValidator.valid?("is", "multipleselectfield")
    refute SmartSuite::FilterValidator.valid?("is", "linkedrecordfield")
  end

  def test_valid_returns_true_for_nil_field_type
    # Can't validate without field type info
    assert SmartSuite::FilterValidator.valid?("any_operator", nil)
  end

  def test_valid_returns_true_for_unknown_field_type
    # Unknown field types are not validated
    assert SmartSuite::FilterValidator.valid?("any_operator", "customfield")
  end

  def test_valid_is_case_insensitive
    assert SmartSuite::FilterValidator.valid?("IS", "TEXTFIELD")
    assert SmartSuite::FilterValidator.valid?("Contains", "TextField")
  end

  # ============================================================================
  # validate! Tests
  # ============================================================================

  def test_validate_returns_true_for_valid_combination
    assert SmartSuite::FilterValidator.validate!("status", "is", "statusfield")
    assert SmartSuite::FilterValidator.validate!("amount", "is_greater_than", "numberfield")
  end

  def test_validate_returns_false_for_invalid_combination_non_strict
    refute SmartSuite::FilterValidator.validate!("amount", "contains", "numberfield")
    refute SmartSuite::FilterValidator.validate!("status", "is_greater_than", "statusfield")
  end

  def test_validate_raises_error_in_strict_mode
    error = assert_raises(ArgumentError) do
      SmartSuite::FilterValidator.validate!("amount", "contains", "numberfield", strict: true)
    end

    assert_match(/Invalid operator 'contains'/, error.message)
    assert_match(/numberfield/, error.message)
    assert_match(/Valid operators:/, error.message)
  end

  def test_validate_error_includes_suggestion_when_available
    error = assert_raises(ArgumentError) do
      SmartSuite::FilterValidator.validate!("tags", "is", "multipleselectfield", strict: true)
    end

    assert_match(/Did you mean 'has_any_of'\?/, error.message)
  end

  def test_validate_returns_true_for_nil_field_type
    assert SmartSuite::FilterValidator.validate!("field", "any_op", nil, strict: true)
  end

  # ============================================================================
  # suggest_operator Tests
  # ============================================================================

  def test_suggest_has_any_of_for_is_on_multiple_select
    suggestion = SmartSuite::FilterValidator.suggest_operator("is", "multipleselectfield")
    assert_equal "has_any_of", suggestion
  end

  def test_suggest_is_any_of_for_has_any_of_on_single_select
    suggestion = SmartSuite::FilterValidator.suggest_operator("has_any_of", "statusfield")
    assert_equal "is_any_of", suggestion
  end

  def test_suggest_has_any_of_for_is_on_user_field
    suggestion = SmartSuite::FilterValidator.suggest_operator("is", "userfield")
    assert_equal "has_any_of", suggestion
  end

  def test_suggest_has_any_of_for_is_on_linked_record
    suggestion = SmartSuite::FilterValidator.suggest_operator("is", "linkedrecordfield")
    assert_equal "has_any_of", suggestion
  end

  def test_suggest_is_for_numeric_ops_on_text_field
    suggestion = SmartSuite::FilterValidator.suggest_operator("is_equal_to", "textfield")
    assert_equal "is", suggestion
  end

  def test_suggest_is_equal_to_for_contains_on_number_field
    suggestion = SmartSuite::FilterValidator.suggest_operator("contains", "numberfield")
    assert_equal "is_equal_to", suggestion
  end

  def test_suggest_returns_nil_for_no_suggestion
    # Some invalid combinations don't have obvious suggestions
    suggestion = SmartSuite::FilterValidator.suggest_operator("is_overdue", "textfield")
    assert_nil suggestion
  end

  # ============================================================================
  # Field Type Coverage Tests
  # ============================================================================

  def test_all_text_field_types_use_text_operators
    text_types = %w[textfield textareafield richtextareafield emailfield phonefield linkfield
                    fullnamefield addressfield smartdocfield]

    text_types.each do |field_type|
      assert SmartSuite::FilterValidator.valid?("contains", field_type),
             "Expected 'contains' to be valid for #{field_type}"
      refute SmartSuite::FilterValidator.valid?("is_greater_than", field_type),
             "Expected 'is_greater_than' to be invalid for #{field_type}"
    end
  end

  def test_all_numeric_field_types_use_numeric_operators
    numeric_types = %w[numberfield currencyfield ratingfield percentfield durationfield votefield]

    numeric_types.each do |field_type|
      assert SmartSuite::FilterValidator.valid?("is_greater_than", field_type),
             "Expected 'is_greater_than' to be valid for #{field_type}"
      refute SmartSuite::FilterValidator.valid?("contains", field_type),
             "Expected 'contains' to be invalid for #{field_type}"
    end
  end

  def test_all_date_field_types_use_date_operators
    date_types = %w[datefield daterangefield firstcreatedfield lastupdatedfield]

    date_types.each do |field_type|
      assert SmartSuite::FilterValidator.valid?("is_before", field_type),
             "Expected 'is_before' to be valid for #{field_type}"
      refute SmartSuite::FilterValidator.valid?("contains", field_type),
             "Expected 'contains' to be invalid for #{field_type}"
    end
  end

  def test_all_user_field_types_use_user_operators
    user_types = %w[userfield assignedtofield createdbyfield]

    user_types.each do |field_type|
      assert SmartSuite::FilterValidator.valid?("has_any_of", field_type),
             "Expected 'has_any_of' to be valid for #{field_type}"
      refute SmartSuite::FilterValidator.valid?("is", field_type),
             "Expected 'is' to be invalid for #{field_type}"
    end
  end
end
