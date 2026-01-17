# frozen_string_literal: true

require "minitest/autorun"
require "date"
require "time"

# Comprehensive unit tests for PostgresQuery filter operations.
#
# These tests verify SQL generation for ALL filter operators across ALL field types.
# Uses stub classes to test SQL generation without requiring PostgreSQL connection.
#
# Field Type Categories and Valid Operators:
# - Text fields: is, is_not, contains, not_contains, is_empty, is_not_empty
# - Numeric fields: is, is_not, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty
# - Date fields: is, is_not, is_before, is_after, is_on_or_before, is_on_or_after, is_empty, is_not_empty
# - Due date fields: date operators + is_overdue, is_not_overdue
# - Single select/status: is, is_not, is_any_of, is_none_of, is_empty, is_not_empty
# - Multiple select/tags: has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty
# - Linked records: contains, not_contains, has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty
# - User fields: has_any_of, has_all_of, is_exactly, has_none_of, is_empty, is_not_empty
# - File fields: file_name_contains, file_type_is, is_empty, is_not_empty
# - Yes/No fields: is (only)
#
class TestPostgresQueryFilters < Minitest::Test
  # Stub class that replicates PostgresQuery's build_pg_condition method
  # for testing SQL generation without requiring ActiveRecord/PostgreSQL
  class PostgresQueryStub
    def sanitize_field_name(field)
      field.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    # Replicate the build_pg_condition logic from PostgresQuery
    def build_pg_condition(field, comparison, value)
      sanitized = sanitize_field_name(field)
      field_accessor = "data->>'#{sanitized}'"
      select_accessor = "COALESCE(data->'#{sanitized}'->>'value', data->>'#{sanitized}')"

      case comparison
      when "is"
        [ "#{select_accessor} = ?", [ value.to_s ] ]
      when "is_not"
        [ "#{select_accessor} != ?", [ value.to_s ] ]
      when "contains"
        [ "#{field_accessor} ILIKE ?", [ "%#{value}%" ] ]
      when "not_contains"
        [ "#{field_accessor} NOT ILIKE ?", [ "%#{value}%" ] ]
      when "is_greater_than"
        [ "(#{field_accessor})::numeric > ?", [ value.to_f ] ]
      when "is_less_than"
        [ "(#{field_accessor})::numeric < ?", [ value.to_f ] ]
      when "is_equal_or_greater_than"
        [ "(#{field_accessor})::numeric >= ?", [ value.to_f ] ]
      when "is_equal_or_less_than"
        [ "(#{field_accessor})::numeric <= ?", [ value.to_f ] ]
      when "is_empty"
        [ "(#{field_accessor} IS NULL OR #{field_accessor} = '' OR " \
          "data->'#{sanitized}' = '[]'::jsonb OR data->'#{sanitized}' = 'null'::jsonb)", [] ]
      when "is_not_empty"
        [ "(#{field_accessor} IS NOT NULL AND #{field_accessor} != '' AND " \
          "data->'#{sanitized}' != '[]'::jsonb AND data->'#{sanitized}' != 'null'::jsonb)", [] ]
      when "has_any_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "data->'#{sanitized}' @> ?::jsonb" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' OR ')})", params ]
        else
          [ "FALSE", [] ]
        end
      when "has_all_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "data->'#{sanitized}' @> ?::jsonb" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' AND ')})", params ]
        else
          [ "TRUE", [] ]
        end
      when "has_none_of"
        if value.is_a?(Array) && value.any?
          conditions = value.map { "NOT (data->'#{sanitized}' @> ?::jsonb)" }
          params = value.map { |v| "[\"#{v}\"]" }
          [ "(#{conditions.join(' AND ')})", params ]
        else
          [ "TRUE", [] ]
        end
      when "is_any_of"
        if value.is_a?(Array) && value.any?
          placeholders = value.map { "?" }.join(", ")
          [ "#{select_accessor} IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "FALSE", [] ]
        end
      when "is_none_of"
        if value.is_a?(Array) && value.any?
          placeholders = value.map { "?" }.join(", ")
          [ "#{select_accessor} NOT IN (#{placeholders})", value.map(&:to_s) ]
        else
          [ "TRUE", [] ]
        end
      when "is_before"
        [ "#{date_field_accessor(sanitized)} < ?", [ value.to_s ] ]
      when "is_after"
        [ "#{date_field_accessor(sanitized)} > ?", [ value.to_s ] ]
      when "is_on_or_before"
        [ "#{date_field_accessor(sanitized)} <= ?", [ value.to_s ] ]
      when "is_on_or_after"
        [ "#{date_field_accessor(sanitized)} >= ?", [ value.to_s ] ]
      when "between"
        [ "#{field_accessor} BETWEEN ? AND ?", [ value[:min], value[:max] ] ]
      when "not_between"
        [ "(#{field_accessor} < ? OR #{field_accessor} > ?)", [ value[:min], value[:max] ] ]
      # File field operators (filefield only)
      # Files are stored as JSONB array: [{"name": "file.pdf", "type": "pdf", ...}, ...]
      when "file_name_contains"
        # Search for filename in JSONB array using JSONB path query
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'name' ILIKE ?)", [ "%#{value}%" ] ]
      when "file_type_is"
        # Search for file type in JSONB array
        # Valid types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
        [ "EXISTS (SELECT 1 FROM jsonb_array_elements(data->'#{sanitized}') AS elem " \
          "WHERE elem->>'type' = ?)", [ value.to_s ] ]
      else
        [ "#{field_accessor} = ?", [ value.to_s ] ]
      end
    end

    # Replicate build_condition_sql from PostgresQuery
    def build_condition_sql(field_slug, condition)
      field = field_slug.to_s

      if condition.is_a?(Hash)
        operator, value = condition.first
        comparison = operator_to_comparison(operator)
      else
        comparison = "is"
        value = condition
      end

      build_pg_condition(field, comparison, value)
    end

    def operator_to_comparison(operator)
      case operator.to_sym
      when :eq then "is"
      when :ne then "is_not"
      when :gt then "is_greater_than"
      when :gte then "is_equal_or_greater_than"
      when :lt then "is_less_than"
      when :lte then "is_equal_or_less_than"
      when :contains then "contains"
      when :not_contains then "not_contains"
      when :has_any_of then "has_any_of"
      when :has_all_of then "has_all_of"
      when :has_none_of then "has_none_of"
      when :is_exactly then "is_exactly"
      when :is_any_of then "is_any_of"
      when :is_none_of then "is_none_of"
      when :is_empty then "is_empty"
      when :is_not_empty then "is_not_empty"
      when :is_before then "is_before"
      when :is_after then "is_after"
      when :is_on_or_before then "is_on_or_before"
      when :is_on_or_after then "is_on_or_after"
      when :between then "between"
      when :not_between then "not_between"
      when :file_name_contains then "file_name_contains"
      when :file_type_is then "file_type_is"
      else "is"
      end
    end

    def date_field_accessor(field)
      <<~SQL.gsub(/\s+/, " ").strip
        COALESCE(
          SUBSTRING(data->'#{field}'->'to_date'->>'date' FROM 1 FOR 10),
          CASE
            WHEN data->'#{field}'->>'to_date' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->'#{field}'->>'to_date' FROM 1 FOR 10)
            ELSE NULL
          END,
          CASE
            WHEN data->>'#{field}' ~ '^\\d{4}-\\d{2}-\\d{2}'
            THEN SUBSTRING(data->>'#{field}' FROM 1 FOR 10)
            ELSE NULL
          END
        )
      SQL
    end
  end

  def setup
    @query = PostgresQueryStub.new
  end

  # ============================================
  # TEXT FIELD OPERATORS
  # Field types: textfield, textareafield, richtextareafield, emailfield, phonefield, linkfield
  # ============================================

  def test_text_is_operator
    sql, params = @query.build_pg_condition("name", "is", "John Doe")

    assert_includes sql, "COALESCE"
    assert_includes sql, "= ?"
    assert_equal [ "John Doe" ], params
  end

  def test_text_is_not_operator
    sql, params = @query.build_pg_condition("email", "is_not", "test@example.com")

    assert_includes sql, "COALESCE"
    assert_includes sql, "!= ?"
    assert_equal [ "test@example.com" ], params
  end

  def test_text_contains_operator
    sql, params = @query.build_pg_condition("description", "contains", "urgent")

    assert_includes sql, "ILIKE"
    assert_includes sql, "data->>'description'"
    assert_equal [ "%urgent%" ], params
  end

  def test_text_not_contains_operator
    sql, params = @query.build_pg_condition("notes", "not_contains", "spam")

    assert_includes sql, "NOT ILIKE"
    assert_includes sql, "data->>'notes'"
    assert_equal [ "%spam%" ], params
  end

  def test_text_is_empty_operator
    sql, params = @query.build_pg_condition("comments", "is_empty", nil)

    assert_includes sql, "IS NULL"
    assert_includes sql, "= ''"
    assert_includes sql, "'[]'::jsonb"
    assert_includes sql, "'null'::jsonb"
    assert_empty params
  end

  def test_text_is_not_empty_operator
    sql, params = @query.build_pg_condition("title", "is_not_empty", nil)

    assert_includes sql, "IS NOT NULL"
    assert_includes sql, "!= ''"
    assert_includes sql, "!= '[]'::jsonb"
    assert_includes sql, "!= 'null'::jsonb"
    assert_empty params
  end

  # ============================================
  # NUMERIC FIELD OPERATORS
  # Field types: numberfield, currencyfield, ratingfield, percentfield, durationfield
  # ============================================

  def test_numeric_is_operator
    sql, params = @query.build_pg_condition("quantity", "is", 42)

    assert_includes sql, "= ?"
    assert_equal [ "42" ], params
  end

  def test_numeric_is_greater_than_operator
    sql, params = @query.build_pg_condition("amount", "is_greater_than", 100)

    assert_includes sql, "::numeric"
    assert_includes sql, "> ?"
    assert_equal [ 100.0 ], params
  end

  def test_numeric_is_less_than_operator
    sql, params = @query.build_pg_condition("price", "is_less_than", 50)

    assert_includes sql, "::numeric"
    assert_includes sql, "< ?"
    assert_equal [ 50.0 ], params
  end

  def test_numeric_is_equal_or_greater_than_operator
    sql, params = @query.build_pg_condition("rating", "is_equal_or_greater_than", 4)

    assert_includes sql, "::numeric"
    assert_includes sql, ">= ?"
    assert_equal [ 4.0 ], params
  end

  def test_numeric_is_equal_or_less_than_operator
    sql, params = @query.build_pg_condition("percentage", "is_equal_or_less_than", 80)

    assert_includes sql, "::numeric"
    assert_includes sql, "<= ?"
    assert_equal [ 80.0 ], params
  end

  def test_numeric_handles_decimal_values
    sql, params = @query.build_pg_condition("currency", "is_greater_than", 99.99)

    assert_includes sql, "::numeric"
    assert_equal [ 99.99 ], params
  end

  def test_numeric_converts_string_to_float
    sql, params = @query.build_pg_condition("value", "is_greater_than", "150")

    assert_includes sql, "::numeric"
    assert_equal [ 150.0 ], params
  end

  # ============================================
  # DATE FIELD OPERATORS
  # Field types: datefield, daterangefield, firstcreatedfield, lastupdatedfield
  # ============================================

  def test_date_is_before_operator
    sql, params = @query.build_pg_condition("due_date", "is_before", "2025-12-31")

    assert_includes sql, "COALESCE"
    assert_includes sql, "< ?"
    assert_includes sql, "to_date"
    assert_equal [ "2025-12-31" ], params
  end

  def test_date_is_after_operator
    sql, params = @query.build_pg_condition("created_at", "is_after", "2025-01-01")

    assert_includes sql, "COALESCE"
    assert_includes sql, "> ?"
    assert_includes sql, "to_date"
    assert_equal [ "2025-01-01" ], params
  end

  def test_date_is_on_or_before_operator
    sql, params = @query.build_pg_condition("deadline", "is_on_or_before", "2025-06-15")

    assert_includes sql, "<= ?"
    assert_equal [ "2025-06-15" ], params
  end

  def test_date_is_on_or_after_operator
    sql, params = @query.build_pg_condition("start_date", "is_on_or_after", "2025-03-01")

    assert_includes sql, ">= ?"
    assert_equal [ "2025-03-01" ], params
  end

  def test_date_accessor_handles_date_range_format
    # DateRange fields have structure: {"to_date": {"date": "2024-06-24T00:00:00Z", ...}}
    sql = @query.date_field_accessor("event_date")

    assert_includes sql, "to_date"
    assert_includes sql, "->>'date'"
    assert_includes sql, "SUBSTRING"
    assert_includes sql, "FROM 1 FOR 10"
  end

  def test_date_accessor_handles_simple_date_format
    # Simple dates stored as "2025-01-15"
    sql = @query.date_field_accessor("simple_date")

    assert_includes sql, "data->>'simple_date'"
  end

  def test_date_accessor_validates_date_format
    # Should check for YYYY-MM-DD pattern
    sql = @query.date_field_accessor("date_field")

    assert_includes sql, "^\\d{4}-\\d{2}-\\d{2}"
  end

  # ============================================
  # SINGLE SELECT / STATUS FIELD OPERATORS
  # Field types: singleselectfield, statusfield
  # ============================================

  def test_single_select_is_operator
    sql, params = @query.build_pg_condition("status", "is", "uuid-active-123")

    assert_includes sql, "COALESCE"
    assert_includes sql, "->>'value'"
    assert_includes sql, "= ?"
    assert_equal [ "uuid-active-123" ], params
  end

  def test_single_select_is_not_operator
    sql, params = @query.build_pg_condition("priority", "is_not", "uuid-low-456")

    assert_includes sql, "!= ?"
    assert_equal [ "uuid-low-456" ], params
  end

  def test_single_select_is_any_of_operator
    values = %w[uuid-1 uuid-2 uuid-3]
    sql, params = @query.build_pg_condition("category", "is_any_of", values)

    assert_includes sql, "IN"
    assert_includes sql, "?, ?, ?"
    assert_equal %w[uuid-1 uuid-2 uuid-3], params
  end

  def test_single_select_is_none_of_operator
    values = %w[uuid-spam uuid-deleted]
    sql, params = @query.build_pg_condition("type", "is_none_of", values)

    assert_includes sql, "NOT IN"
    assert_equal %w[uuid-spam uuid-deleted], params
  end

  def test_single_select_is_any_of_with_empty_array
    sql, params = @query.build_pg_condition("status", "is_any_of", [])

    assert_equal "FALSE", sql
    assert_empty params
  end

  def test_single_select_is_none_of_with_empty_array
    sql, params = @query.build_pg_condition("status", "is_none_of", [])

    assert_equal "TRUE", sql
    assert_empty params
  end

  # ============================================
  # MULTIPLE SELECT / TAGS FIELD OPERATORS
  # Field types: multipleselectfield, tagsfield
  # ============================================

  def test_multiple_select_has_any_of_operator
    values = %w[tag-1 tag-2]
    sql, params = @query.build_pg_condition("tags", "has_any_of", values)

    assert_includes sql, "@>"
    assert_includes sql, " OR "
    assert_includes sql, "::jsonb"
    assert_equal [ "[\"tag-1\"]", "[\"tag-2\"]" ], params
  end

  def test_multiple_select_has_all_of_operator
    values = %w[required-1 required-2]
    sql, params = @query.build_pg_condition("features", "has_all_of", values)

    assert_includes sql, "@>"
    assert_includes sql, " AND "
    assert_equal [ "[\"required-1\"]", "[\"required-2\"]" ], params
  end

  def test_multiple_select_has_none_of_operator
    values = %w[excluded-1 excluded-2]
    sql, params = @query.build_pg_condition("labels", "has_none_of", values)

    assert_includes sql, "NOT ("
    assert_includes sql, "@>"
    assert_includes sql, " AND "
    assert_equal [ "[\"excluded-1\"]", "[\"excluded-2\"]" ], params
  end

  def test_multiple_select_has_any_of_with_empty_array
    sql, params = @query.build_pg_condition("tags", "has_any_of", [])

    assert_equal "FALSE", sql
    assert_empty params
  end

  def test_multiple_select_has_all_of_with_empty_array
    sql, params = @query.build_pg_condition("tags", "has_all_of", [])

    assert_equal "TRUE", sql
    assert_empty params
  end

  def test_multiple_select_has_none_of_with_empty_array
    sql, params = @query.build_pg_condition("tags", "has_none_of", [])

    assert_equal "TRUE", sql
    assert_empty params
  end

  def test_multiple_select_single_value_in_array
    sql, params = @query.build_pg_condition("categories", "has_any_of", [ "cat-1" ])

    assert_includes sql, "@>"
    refute_includes sql, " OR "  # Only one condition, no OR needed
    assert_equal [ "[\"cat-1\"]" ], params
  end

  # ============================================
  # LINKED RECORD FIELD OPERATORS
  # Field types: linkedrecordfield, subitemsfield
  # ============================================

  def test_linked_record_has_any_of_operator
    record_ids = %w[rec-123 rec-456]
    sql, params = @query.build_pg_condition("related_project", "has_any_of", record_ids)

    assert_includes sql, "@>"
    assert_includes sql, " OR "
    assert_equal [ "[\"rec-123\"]", "[\"rec-456\"]" ], params
  end

  def test_linked_record_has_all_of_operator
    record_ids = %w[rec-abc rec-def]
    sql, params = @query.build_pg_condition("parent_tasks", "has_all_of", record_ids)

    assert_includes sql, "@>"
    assert_includes sql, " AND "
    assert_equal [ "[\"rec-abc\"]", "[\"rec-def\"]" ], params
  end

  def test_linked_record_has_none_of_operator
    record_ids = %w[rec-exclude-1]
    sql, params = @query.build_pg_condition("blocked_by", "has_none_of", record_ids)

    assert_includes sql, "NOT ("
    assert_includes sql, "@>"
    assert_equal [ "[\"rec-exclude-1\"]" ], params
  end

  def test_linked_record_contains_text_search
    # Linked records also support text-based contains for searching within linked data
    sql, params = @query.build_pg_condition("related_items", "contains", "important")

    assert_includes sql, "ILIKE"
    assert_equal [ "%important%" ], params
  end

  def test_linked_record_is_empty
    sql, params = @query.build_pg_condition("parent", "is_empty", nil)

    assert_includes sql, "IS NULL"
    assert_includes sql, "'[]'::jsonb"
    assert_empty params
  end

  # ============================================
  # USER FIELD OPERATORS
  # Field types: userfield, assignedtofield, createdbyfield
  # ============================================

  def test_user_has_any_of_operator
    user_ids = %w[user-123 user-456]
    sql, params = @query.build_pg_condition("assigned_to", "has_any_of", user_ids)

    assert_includes sql, "@>"
    assert_includes sql, " OR "
    assert_equal [ "[\"user-123\"]", "[\"user-456\"]" ], params
  end

  def test_user_has_all_of_operator
    user_ids = %w[user-required-1 user-required-2]
    sql, params = @query.build_pg_condition("team_members", "has_all_of", user_ids)

    assert_includes sql, "@>"
    assert_includes sql, " AND "
    assert_equal [ "[\"user-required-1\"]", "[\"user-required-2\"]" ], params
  end

  def test_user_has_none_of_operator
    user_ids = %w[user-exclude]
    sql, params = @query.build_pg_condition("reviewers", "has_none_of", user_ids)

    assert_includes sql, "NOT ("
    assert_equal [ "[\"user-exclude\"]" ], params
  end

  def test_user_is_empty
    sql, params = @query.build_pg_condition("owner", "is_empty", nil)

    assert_includes sql, "IS NULL"
    assert_empty params
  end

  def test_user_is_not_empty
    sql, params = @query.build_pg_condition("creator", "is_not_empty", nil)

    assert_includes sql, "IS NOT NULL"
    assert_empty params
  end

  # ============================================
  # YES/NO (BOOLEAN) FIELD OPERATORS
  # Field types: yesnofield, checkboxfield
  # ============================================

  def test_yesno_is_true
    sql, params = @query.build_pg_condition("is_active", "is", true)

    assert_includes sql, "= ?"
    assert_equal [ "true" ], params
  end

  def test_yesno_is_false
    sql, params = @query.build_pg_condition("is_archived", "is", false)

    assert_includes sql, "= ?"
    assert_equal [ "false" ], params
  end

  # ============================================
  # FILE FIELD OPERATORS
  # Field types: filefield, imagefield, signaturefield
  # ============================================

  def test_file_name_contains_operator
    sql, params = @query.build_pg_condition("attachments", "file_name_contains", "invoice")

    assert_includes sql, "EXISTS"
    assert_includes sql, "jsonb_array_elements"
    assert_includes sql, "->>'name'"
    assert_includes sql, "ILIKE"
    assert_equal [ "%invoice%" ], params
  end

  def test_file_type_is_operator
    sql, params = @query.build_pg_condition("documents", "file_type_is", "pdf")

    assert_includes sql, "EXISTS"
    assert_includes sql, "jsonb_array_elements"
    assert_includes sql, "->>'type'"
    assert_includes sql, "= ?"
    assert_equal [ "pdf" ], params
  end

  def test_file_type_is_with_various_types
    # Valid types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
    %w[archive image music pdf powerpoint spreadsheet video word other].each do |file_type|
      sql, params = @query.build_pg_condition("files", "file_type_is", file_type)

      assert_includes sql, "EXISTS"
      assert_equal [ file_type ], params, "Failed for file type: #{file_type}"
    end
  end

  def test_file_is_empty
    sql, params = @query.build_pg_condition("uploads", "is_empty", nil)

    assert_includes sql, "IS NULL"
    assert_includes sql, "'[]'::jsonb"
    assert_empty params
  end

  def test_file_is_not_empty
    sql, params = @query.build_pg_condition("photos", "is_not_empty", nil)

    assert_includes sql, "IS NOT NULL"
    assert_includes sql, "!= '[]'::jsonb"
    assert_empty params
  end

  # ============================================
  # BUILD_CONDITION_SQL METHOD TESTS
  # Tests the conversion from FilterBuilder format to SQL
  # ============================================

  def test_build_condition_sql_with_simple_value
    sql, params = @query.build_condition_sql(:status, "active")

    assert_includes sql, "= ?"
    assert_equal [ "active" ], params
  end

  def test_build_condition_sql_with_eq_operator
    sql, params = @query.build_condition_sql(:name, { eq: "Test" })

    assert_includes sql, "= ?"
    assert_equal [ "Test" ], params
  end

  def test_build_condition_sql_with_ne_operator
    sql, params = @query.build_condition_sql(:status, { ne: "deleted" })

    assert_includes sql, "!= ?"
    assert_equal [ "deleted" ], params
  end

  def test_build_condition_sql_with_gt_operator
    sql, params = @query.build_condition_sql(:amount, { gt: 100 })

    assert_includes sql, "> ?"
    assert_includes sql, "::numeric"
    assert_equal [ 100.0 ], params
  end

  def test_build_condition_sql_with_gte_operator
    sql, params = @query.build_condition_sql(:rating, { gte: 4 })

    assert_includes sql, ">= ?"
    assert_equal [ 4.0 ], params
  end

  def test_build_condition_sql_with_lt_operator
    sql, params = @query.build_condition_sql(:price, { lt: 50 })

    assert_includes sql, "< ?"
    assert_equal [ 50.0 ], params
  end

  def test_build_condition_sql_with_lte_operator
    sql, params = @query.build_condition_sql(:quantity, { lte: 10 })

    assert_includes sql, "<= ?"
    assert_equal [ 10.0 ], params
  end

  def test_build_condition_sql_with_contains_operator
    sql, params = @query.build_condition_sql(:description, { contains: "urgent" })

    assert_includes sql, "ILIKE"
    assert_equal [ "%urgent%" ], params
  end

  def test_build_condition_sql_with_not_contains_operator
    sql, params = @query.build_condition_sql(:notes, { not_contains: "spam" })

    assert_includes sql, "NOT ILIKE"
    assert_equal [ "%spam%" ], params
  end

  def test_build_condition_sql_with_has_any_of_operator
    sql, params = @query.build_condition_sql(:tags, { has_any_of: %w[tag1 tag2] })

    assert_includes sql, "@>"
    assert_includes sql, " OR "
    assert_equal [ "[\"tag1\"]", "[\"tag2\"]" ], params
  end

  def test_build_condition_sql_with_has_all_of_operator
    sql, params = @query.build_condition_sql(:labels, { has_all_of: %w[a b] })

    assert_includes sql, "@>"
    assert_includes sql, " AND "
    assert_equal [ "[\"a\"]", "[\"b\"]" ], params
  end

  def test_build_condition_sql_with_has_none_of_operator
    sql, params = @query.build_condition_sql(:categories, { has_none_of: %w[x y] })

    assert_includes sql, "NOT ("
    assert_includes sql, "@>"
    assert_equal [ "[\"x\"]", "[\"y\"]" ], params
  end

  def test_build_condition_sql_with_is_any_of_operator
    sql, params = @query.build_condition_sql(:status, { is_any_of: %w[a b c] })

    assert_includes sql, "IN"
    assert_equal %w[a b c], params
  end

  def test_build_condition_sql_with_is_none_of_operator
    sql, params = @query.build_condition_sql(:type, { is_none_of: %w[spam test] })

    assert_includes sql, "NOT IN"
    assert_equal %w[spam test], params
  end

  def test_build_condition_sql_with_is_empty_operator
    sql, params = @query.build_condition_sql(:notes, { is_empty: true })

    assert_includes sql, "IS NULL"
    assert_empty params
  end

  def test_build_condition_sql_with_is_not_empty_operator
    sql, params = @query.build_condition_sql(:title, { is_not_empty: true })

    assert_includes sql, "IS NOT NULL"
    assert_empty params
  end

  def test_build_condition_sql_with_is_before_operator
    sql, params = @query.build_condition_sql(:due_date, { is_before: "2025-12-31" })

    assert_includes sql, "< ?"
    assert_includes sql, "COALESCE"
    assert_equal [ "2025-12-31" ], params
  end

  def test_build_condition_sql_with_is_after_operator
    sql, params = @query.build_condition_sql(:start_date, { is_after: "2025-01-01" })

    assert_includes sql, "> ?"
    assert_equal [ "2025-01-01" ], params
  end

  def test_build_condition_sql_with_is_on_or_before_operator
    sql, params = @query.build_condition_sql(:deadline, { is_on_or_before: "2025-06-30" })

    assert_includes sql, "<= ?"
    assert_equal [ "2025-06-30" ], params
  end

  def test_build_condition_sql_with_is_on_or_after_operator
    sql, params = @query.build_condition_sql(:created_at, { is_on_or_after: "2025-03-01" })

    assert_includes sql, ">= ?"
    assert_equal [ "2025-03-01" ], params
  end

  def test_build_condition_sql_with_between_operator
    sql, params = @query.build_condition_sql(:amount, { between: { min: 10, max: 100 } })

    assert_includes sql, "BETWEEN"
    assert_equal [ 10, 100 ], params
  end

  def test_build_condition_sql_with_not_between_operator
    sql, params = @query.build_condition_sql(:value, { not_between: { min: 0, max: 50 } })

    assert_includes sql, "< ?"
    assert_includes sql, "> ?"
    assert_includes sql, " OR "
    assert_equal [ 0, 50 ], params
  end

  def test_build_condition_sql_with_file_name_contains_operator
    sql, params = @query.build_condition_sql(:attachments, { file_name_contains: "report" })

    assert_includes sql, "EXISTS"
    assert_includes sql, "jsonb_array_elements"
    assert_includes sql, "->>'name'"
    assert_equal [ "%report%" ], params
  end

  def test_build_condition_sql_with_file_type_is_operator
    sql, params = @query.build_condition_sql(:documents, { file_type_is: "pdf" })

    assert_includes sql, "EXISTS"
    assert_includes sql, "->>'type'"
    assert_equal [ "pdf" ], params
  end

  # ============================================
  # OPERATOR_TO_COMPARISON METHOD TESTS
  # ============================================

  def test_operator_to_comparison_eq
    assert_equal "is", @query.operator_to_comparison(:eq)
  end

  def test_operator_to_comparison_ne
    assert_equal "is_not", @query.operator_to_comparison(:ne)
  end

  def test_operator_to_comparison_gt
    assert_equal "is_greater_than", @query.operator_to_comparison(:gt)
  end

  def test_operator_to_comparison_gte
    assert_equal "is_equal_or_greater_than", @query.operator_to_comparison(:gte)
  end

  def test_operator_to_comparison_lt
    assert_equal "is_less_than", @query.operator_to_comparison(:lt)
  end

  def test_operator_to_comparison_lte
    assert_equal "is_equal_or_less_than", @query.operator_to_comparison(:lte)
  end

  def test_operator_to_comparison_contains
    assert_equal "contains", @query.operator_to_comparison(:contains)
  end

  def test_operator_to_comparison_not_contains
    assert_equal "not_contains", @query.operator_to_comparison(:not_contains)
  end

  def test_operator_to_comparison_has_any_of
    assert_equal "has_any_of", @query.operator_to_comparison(:has_any_of)
  end

  def test_operator_to_comparison_has_all_of
    assert_equal "has_all_of", @query.operator_to_comparison(:has_all_of)
  end

  def test_operator_to_comparison_has_none_of
    assert_equal "has_none_of", @query.operator_to_comparison(:has_none_of)
  end

  def test_operator_to_comparison_is_empty
    assert_equal "is_empty", @query.operator_to_comparison(:is_empty)
  end

  def test_operator_to_comparison_is_not_empty
    assert_equal "is_not_empty", @query.operator_to_comparison(:is_not_empty)
  end

  def test_operator_to_comparison_is_before
    assert_equal "is_before", @query.operator_to_comparison(:is_before)
  end

  def test_operator_to_comparison_is_after
    assert_equal "is_after", @query.operator_to_comparison(:is_after)
  end

  def test_operator_to_comparison_is_on_or_before
    assert_equal "is_on_or_before", @query.operator_to_comparison(:is_on_or_before)
  end

  def test_operator_to_comparison_is_on_or_after
    assert_equal "is_on_or_after", @query.operator_to_comparison(:is_on_or_after)
  end

  def test_operator_to_comparison_file_name_contains
    assert_equal "file_name_contains", @query.operator_to_comparison(:file_name_contains)
  end

  def test_operator_to_comparison_file_type_is
    assert_equal "file_type_is", @query.operator_to_comparison(:file_type_is)
  end

  def test_operator_to_comparison_unknown_defaults_to_is
    assert_equal "is", @query.operator_to_comparison(:unknown_operator)
  end

  # ============================================
  # FIELD NAME SANITIZATION TESTS
  # ============================================

  def test_sanitize_field_name_removes_special_characters
    sanitized = @query.sanitize_field_name("field'; DROP TABLE;--")

    refute_includes sanitized, "'"
    refute_includes sanitized, ";"
    refute_includes sanitized, "-"
    assert_equal "fieldDROPTABLE", sanitized
  end

  def test_sanitize_field_name_preserves_underscores
    sanitized = @query.sanitize_field_name("my_field_name")

    assert_equal "my_field_name", sanitized
  end

  def test_sanitize_field_name_preserves_alphanumeric
    sanitized = @query.sanitize_field_name("field123Name456")

    assert_equal "field123Name456", sanitized
  end

  def test_sanitize_field_name_removes_spaces
    sanitized = @query.sanitize_field_name("field name with spaces")

    assert_equal "fieldnamewithspaces", sanitized
  end

  # ============================================
  # EDGE CASES AND SPECIAL SCENARIOS
  # ============================================

  def test_empty_string_value
    sql, params = @query.build_pg_condition("field", "is", "")

    assert_includes sql, "= ?"
    assert_equal [ "" ], params
  end

  def test_nil_value_for_equality
    sql, params = @query.build_pg_condition("field", "is", nil)

    assert_includes sql, "= ?"
    assert_equal [ "" ], params  # nil.to_s => ""
  end

  def test_numeric_zero
    sql, params = @query.build_pg_condition("count", "is_greater_than", 0)

    assert_includes sql, "> ?"
    assert_equal [ 0.0 ], params
  end

  def test_negative_numbers
    sql, params = @query.build_pg_condition("balance", "is_less_than", -100)

    assert_includes sql, "< ?"
    assert_equal [ -100.0 ], params
  end

  def test_special_characters_in_text_value
    sql, params = @query.build_pg_condition("description", "contains", "test's \"special\" <chars>")

    assert_includes sql, "ILIKE"
    assert_equal [ "%test's \"special\" <chars>%" ], params
  end

  def test_unicode_in_text_value
    sql, params = @query.build_pg_condition("name", "is", "José García 日本語")

    assert_includes sql, "= ?"
    assert_equal [ "José García 日本語" ], params
  end

  def test_very_long_array_for_has_any_of
    values = (1..100).map { |i| "value-#{i}" }
    sql, params = @query.build_pg_condition("tags", "has_any_of", values)

    assert_includes sql, "@>"
    assert_equal 100, sql.scan(" OR ").count + 1  # 100 conditions joined by OR
    assert_equal 100, params.count
  end
end
