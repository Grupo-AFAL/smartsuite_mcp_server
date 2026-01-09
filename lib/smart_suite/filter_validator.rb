# frozen_string_literal: true

module SmartSuite
  # FilterValidator validates that filter operators are compatible with field types.
  #
  # This module provides validation to catch invalid operator-field type combinations
  # early with clear error messages, rather than silently failing or returning wrong results.
  #
  # Warnings can be collected using the warning collection mechanism:
  #   FilterValidator.start_collecting_warnings
  #   # ... perform validations ...
  #   warnings = FilterValidator.collected_warnings
  #   FilterValidator.stop_collecting_warnings
  #
  # @example Valid usage
  #   FilterValidator.validate!("status", "is", "statusfield")  # OK
  #   FilterValidator.validate!("amount", "is_greater_than", "numberfield")  # OK
  #
  # @example Invalid usage - raises ArgumentError
  #   FilterValidator.validate!("amount", "contains", "numberfield")
  #   # => ArgumentError: Invalid operator 'contains' for field type 'numberfield'.
  #   #    Valid operators: is, is_not, is_equal_to, is_not_equal_to, is_greater_than, ...
  module FilterValidator
    # Thread-local warning collection
    WARNINGS_KEY = :smartsuite_filter_warnings

    # Start collecting warnings for this thread
    def self.start_collecting_warnings
      Thread.current[WARNINGS_KEY] = []
    end

    # Stop collecting warnings and clear the collection
    def self.stop_collecting_warnings
      Thread.current[WARNINGS_KEY] = nil
    end

    # Get collected warnings for this thread
    # @return [Array<String>] List of warning messages, or empty array if not collecting
    def self.collected_warnings
      Thread.current[WARNINGS_KEY] || []
    end

    # Check if warning collection is active
    def self.collecting_warnings?
      !Thread.current[WARNINGS_KEY].nil?
    end

    # Add a warning to the collection (if collecting)
    def self.add_warning(message)
      if collecting_warnings?
        Thread.current[WARNINGS_KEY] << message
      end
    end

    # Operators valid for text-based fields
    TEXT_OPERATORS = %w[
      is is_not is_empty is_not_empty contains not_contains does_not_contain
    ].freeze

    # Operators valid for numeric fields
    NUMERIC_OPERATORS = %w[
      is is_not is_equal_to is_not_equal_to
      is_greater_than is_less_than is_equal_or_greater_than is_equal_or_less_than
      is_empty is_not_empty
    ].freeze

    # Operators valid for numeric fields that don't support empty checks
    NUMERIC_NO_EMPTY_OPERATORS = %w[
      is is_not is_equal_to is_not_equal_to
      is_greater_than is_less_than is_equal_or_greater_than is_equal_or_less_than
    ].freeze

    # Operators valid for date fields
    DATE_OPERATORS = %w[
      is is_not is_before is_after is_on_or_before is_on_or_after is_empty is_not_empty
    ].freeze

    # Additional operators for due date fields
    DUE_DATE_OPERATORS = (DATE_OPERATORS + %w[is_overdue is_not_overdue]).freeze

    # Operators valid for single select/status fields
    SINGLE_SELECT_OPERATORS = %w[
      is is_not is_any_of is_none_of is_empty is_not_empty
    ].freeze

    # Operators valid for multiple select/tag fields
    MULTIPLE_SELECT_OPERATORS = %w[
      has_any_of has_all_of is_exactly has_none_of is_empty is_not_empty
    ].freeze

    # Operators valid for linked record fields
    LINKED_RECORD_OPERATORS = %w[
      contains not_contains has_any_of has_all_of is_exactly has_none_of is_empty is_not_empty
    ].freeze

    # Operators valid for user fields
    USER_OPERATORS = %w[
      has_any_of has_all_of is_exactly has_none_of is_empty is_not_empty
    ].freeze

    # Operators valid for file fields
    FILE_OPERATORS = %w[
      file_name_contains file_type_is is_empty is_not_empty
    ].freeze

    # Operators valid for yes/no (boolean) fields
    YESNO_OPERATORS = %w[is].freeze

    # Field type categories
    TEXT_FIELD_TYPES = %w[
      textfield textareafield richtextareafield emailfield phonefield linkfield
      fullnamefield addressfield smartdocfield
    ].freeze

    NUMERIC_FIELD_TYPES = %w[
      numberfield currencyfield ratingfield percentfield durationfield votefield
    ].freeze

    DATE_FIELD_TYPES = %w[
      datefield daterangefield firstcreatedfield lastupdatedfield
    ].freeze

    DUE_DATE_FIELD_TYPES = %w[duedatefield].freeze

    SINGLE_SELECT_FIELD_TYPES = %w[singleselectfield statusfield].freeze

    MULTIPLE_SELECT_FIELD_TYPES = %w[multipleselectfield tagsfield].freeze

    LINKED_RECORD_FIELD_TYPES = %w[linkedrecordfield subitemsfield].freeze

    USER_FIELD_TYPES = %w[userfield assignedtofield createdbyfield].freeze

    FILE_FIELD_TYPES = %w[filefield imagefield signaturefield].freeze

    YESNO_FIELD_TYPES = %w[yesnofield checkboxfield].freeze

    # Auto number doesn't support is_empty/is_not_empty
    AUTO_NUMBER_FIELD_TYPES = %w[autonumberfield].freeze

    # Field types that inherit operators from their return type
    FORMULA_FIELD_TYPES = %w[formulafield lookupfield rollupfield countfield].freeze

    class << self
      # Validate that an operator is valid for a given field type.
      #
      # @param field_slug [String] Field identifier (for error messages)
      # @param operator [String] Filter comparison operator
      # @param field_type [String] SmartSuite field type (e.g., "textfield", "numberfield")
      # @param strict [Boolean] If false, only warn; if true, raise error (default: false)
      # @return [Boolean] true if valid
      # @raise [ArgumentError] if operator is invalid for field type (when strict: true)
      def validate!(field_slug, operator, field_type, strict: false)
        return true if field_type.nil? # Can't validate without field type

        normalized_type = field_type.to_s.downcase
        normalized_op = operator.to_s.downcase

        valid_operators = operators_for_field_type(normalized_type)

        # If we don't know this field type, skip validation (formula fields, etc.)
        return true if valid_operators.nil?

        if valid_operators.include?(normalized_op)
          true
        else
          message = build_error_message(field_slug, normalized_op, normalized_type, valid_operators)

          if strict
            raise ArgumentError, message
          else
            SmartSuite::Logger.warn(message) if defined?(SmartSuite::Logger)
            # Also add to warning collection if active
            FilterValidator.add_warning(message)
            false
          end
        end
      end

      # Check if an operator is valid for a field type (non-raising version).
      #
      # @param operator [String] Filter comparison operator
      # @param field_type [String] SmartSuite field type
      # @return [Boolean] true if valid, false otherwise
      def valid?(operator, field_type)
        return true if field_type.nil?

        normalized_type = field_type.to_s.downcase
        normalized_op = operator.to_s.downcase

        valid_operators = operators_for_field_type(normalized_type)
        return true if valid_operators.nil?

        valid_operators.include?(normalized_op)
      end

      # Get valid operators for a field type.
      #
      # @param field_type [String] SmartSuite field type (lowercase)
      # @return [Array<String>, nil] List of valid operators, or nil if unknown type
      def operators_for_field_type(field_type)
        case field_type
        when *TEXT_FIELD_TYPES
          TEXT_OPERATORS
        when *NUMERIC_FIELD_TYPES
          NUMERIC_OPERATORS
        when *AUTO_NUMBER_FIELD_TYPES
          NUMERIC_NO_EMPTY_OPERATORS
        when *DUE_DATE_FIELD_TYPES
          DUE_DATE_OPERATORS
        when *DATE_FIELD_TYPES
          DATE_OPERATORS
        when *SINGLE_SELECT_FIELD_TYPES
          SINGLE_SELECT_OPERATORS
        when *MULTIPLE_SELECT_FIELD_TYPES
          MULTIPLE_SELECT_OPERATORS
        when *LINKED_RECORD_FIELD_TYPES
          LINKED_RECORD_OPERATORS
        when *USER_FIELD_TYPES
          USER_OPERATORS
        when *FILE_FIELD_TYPES
          FILE_OPERATORS
        when *YESNO_FIELD_TYPES
          YESNO_OPERATORS
        when *FORMULA_FIELD_TYPES
          # Formula fields inherit from return type - can't validate without knowing return type
          nil
        else
          # Unknown field type - skip validation
          nil
        end
      end

      # Suggest the correct operator for a common mistake.
      #
      # @param operator [String] The invalid operator used
      # @param field_type [String] The field type
      # @return [String, nil] Suggested operator, or nil if no suggestion
      def suggest_operator(operator, field_type)
        normalized_type = field_type.to_s.downcase
        normalized_op = operator.to_s.downcase

        case normalized_type
        when *MULTIPLE_SELECT_FIELD_TYPES
          # Common mistake: using 'is' instead of 'has_any_of'
          return "has_any_of" if %w[is is_any_of].include?(normalized_op)
        when *SINGLE_SELECT_FIELD_TYPES
          # Common mistake: using 'has_any_of' instead of 'is_any_of'
          return "is_any_of" if normalized_op == "has_any_of"
          return "is" if normalized_op == "has_any_of" || normalized_op == "contains"
        when *USER_FIELD_TYPES, *LINKED_RECORD_FIELD_TYPES
          # Common mistake: using 'is' instead of 'has_any_of'
          return "has_any_of" if normalized_op == "is"
        when *TEXT_FIELD_TYPES
          # Common mistake: using numeric operators
          return "is" if %w[is_equal_to is_greater_than is_less_than].include?(normalized_op)
        when *NUMERIC_FIELD_TYPES
          # Common mistake: using 'contains' for numbers
          return "is_equal_to" if normalized_op == "contains"
        end

        nil
      end

      private

      # Build a helpful error message for invalid operator usage.
      #
      # @param field_slug [String] Field identifier
      # @param operator [String] The invalid operator
      # @param field_type [String] The field type
      # @param valid_operators [Array<String>] List of valid operators
      # @return [String] Error message
      def build_error_message(field_slug, operator, field_type, valid_operators)
        suggestion = suggest_operator(operator, field_type)
        suggestion_text = suggestion ? " Did you mean '#{suggestion}'?" : ""

        "Invalid operator '#{operator}' for field '#{field_slug}' (#{field_type}). " \
          "Valid operators: #{valid_operators.join(', ')}.#{suggestion_text}"
      end
    end
  end
end
