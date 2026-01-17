# frozen_string_literal: true

module Cache
  # Shared helper methods for building PostgreSQL JSONB conditions.
  #
  # This module extracts common logic used by both PostgresLayer (direct queries)
  # and PostgresQuery (query builder). The two classes use different placeholder
  # styles ($N vs ?) but share the same condition-building patterns.
  #
  # @example Including in a class
  #   class PostgresLayer
  #     include Cache::JsonbConditions
  #   end
  #
  module JsonbConditions
    # Sanitize a field name to prevent SQL injection.
    # Only allows alphanumeric characters and underscores.
    #
    # @param name [String, Symbol] Field name to sanitize
    # @return [String] Sanitized field name
    def sanitize_field_name(name)
      name.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    # Build SQL accessor for date fields that handles SmartSuite's multiple date formats:
    # - Simple date: "2024-06-24" (stored as string)
    # - Date Range: {"to_date": {"date": "2024-06-24T00:00:00Z", ...}, ...}
    # - Due Date: {"to_date": "2024-06-24", ...} (date as string, not nested)
    #
    # Returns NULL when no valid date is present to avoid incorrect comparisons.
    #
    # @param field [String] Field name (will be sanitized)
    # @param sanitized [Boolean] Set to true if field is already sanitized
    # @return [String] SQL expression that extracts the date value
    def date_field_accessor(field, sanitized: false)
      safe_field = sanitized ? field : sanitize_field_name(field)
      <<~SQL.squish
        COALESCE(
          SUBSTRING(data->'#{safe_field}'->'to_date'->>'date' FROM 1 FOR 10),
          CASE
            WHEN data->'#{safe_field}'->>'to_date' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->'#{safe_field}'->>'to_date' FROM 1 FOR 10)
            ELSE NULL
          END,
          CASE
            WHEN data->>'#{safe_field}' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->>'#{safe_field}' FROM 1 FOR 10)
            ELSE NULL
          END
        )
      SQL
    end

    # Build SQL accessor for status/single select fields that handles both:
    # - Simple values: "in_progress" (stored as string)
    # - Object values: {"value": "in_progress", "updated_on": "..."} (statusfield format)
    #
    # @param field [String] Field name (will be sanitized)
    # @param sanitized [Boolean] Set to true if field is already sanitized
    # @return [String] SQL expression using COALESCE
    def select_field_accessor(field, sanitized: false)
      safe_field = sanitized ? field : sanitize_field_name(field)
      <<~SQL.squish
        COALESCE(
          data->'#{safe_field}'->>'value',
          data->>'#{safe_field}'
        )
      SQL
    end

    # Build the SQL expression for checking if a JSONB field is empty.
    # Handles NULL, empty string, empty array [], and JSON null.
    #
    # @param field [String] Sanitized field name
    # @param field_accessor [String] SQL expression to access field as text
    # @return [String] SQL condition (no placeholders)
    def empty_condition_sql(field, field_accessor)
      "(#{field_accessor} IS NULL OR #{field_accessor} = '' OR " \
        "data->'#{field}' = '[]'::jsonb OR data->'#{field}' = 'null'::jsonb)"
    end

    # Build the SQL expression for checking if a JSONB field is not empty.
    #
    # @param field [String] Sanitized field name
    # @param field_accessor [String] SQL expression to access field as text
    # @return [String] SQL condition (no placeholders)
    def not_empty_condition_sql(field, field_accessor)
      "(#{field_accessor} IS NOT NULL AND #{field_accessor} != '' AND " \
        "data->'#{field}' != '[]'::jsonb AND data->'#{field}' != 'null'::jsonb)"
    end

    # Build SQL condition for file_name_contains operator.
    # Files are stored as JSONB array: [{"name": "file.pdf", "type": "pdf", ...}, ...]
    #
    # @param field [String] Sanitized field name
    # @return [String] SQL expression (caller provides placeholder)
    def file_name_contains_sql(field)
      "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{field}') AS elem " \
        "WHERE elem->>'name' ILIKE %s)"
    end

    # Build SQL condition for file_type_is operator.
    # Valid types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
    #
    # @param field [String] Sanitized field name
    # @return [String] SQL expression (caller provides placeholder)
    def file_type_is_sql(field)
      "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{field}') AS elem " \
        "WHERE elem->>'type' = %s)"
    end

    # Build SQL condition for JSONB array containment (has_any_of, has_all_of, has_none_of).
    #
    # @param field [String] Sanitized field name
    # @param values [Array] Values to check
    # @param operator [Symbol] :any (OR), :all (AND), or :none (NOT AND)
    # @param placeholder_builder [Proc] Lambda that returns placeholder for index, e.g., ->(i) { "$#{i}" }
    # @return [Array<String, Array>] [sql_clause, params]
    def array_containment_condition(field, values, operator, placeholder_builder)
      return empty_array_fallback(operator) unless values.is_a?(Array) && values.any?

      conditions = values.map.with_index do |_, i|
        placeholder = placeholder_builder.call(i)
        case operator
        when :any, :all
          "data->'#{field}' @> #{placeholder}::jsonb"
        when :none
          "NOT (data->'#{field}' @> #{placeholder}::jsonb)"
        end
      end

      joiner = operator == :any ? " OR " : " AND "
      params = values.map { |v| "[\"#{v}\"]" }

      [ "(#{conditions.join(joiner)})", params ]
    end

    private

    def empty_array_fallback(operator)
      case operator
      when :any
        [ "FALSE", [] ]
      else
        [ "TRUE", [] ]
      end
    end
  end
end
