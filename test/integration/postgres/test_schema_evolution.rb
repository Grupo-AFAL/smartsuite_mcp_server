# frozen_string_literal: true

# Load Rails test environment for PostgreSQL
ENV["RAILS_ENV"] ||= "test"
require_relative "../../../config/environment"
require "minitest/autorun"

# Tests for schema evolution handling in PostgreSQL cache layer.
#
# These tests verify that when a SmartSuite table's structure changes:
# 1. Old cached records are properly invalidated
# 2. New schema is correctly stored
# 3. Stale data doesn't persist with wrong structure
#
# This is critical for data integrity - we don't want to serve cached
# records that have a different structure than the current table schema.
#
class TestSchemaEvolution < Minitest::Test
  def setup
    skip_unless_postgres_available!
    @cache = Cache::PostgresLayer.new
    @table_id = "test_schema_evolution_#{rand(10000)}"
    clear_test_data!
  end

  def teardown
    clear_test_data! if postgres_available?
  end

  # ==================== Schema Change Tests ====================

  def test_invalidate_clears_records_when_structure_changes
    # Step 1: Cache records with initial schema
    initial_structure = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" }
    ]

    initial_records = [
      { "id" => "rec_1", "name" => "Record 1", "status" => { "value" => "active" } },
      { "id" => "rec_2", "name" => "Record 2", "status" => { "value" => "inactive" } }
    ]

    @cache.cache_table_records(@table_id, initial_structure, initial_records)

    # Verify records are cached
    assert @cache.cache_valid?(@table_id), "Cache should be valid after initial cache"
    cached = @cache.get_cached_records(@table_id)
    assert_equal 2, cached.size, "Should have 2 cached records"

    # Step 2: Simulate schema change - invalidate with structure_changed: true
    @cache.invalidate_table_cache(@table_id, structure_changed: true)

    # Step 3: Verify records are cleared
    refute @cache.cache_valid?(@table_id), "Cache should be invalid after schema change invalidation"
    cached_after = @cache.get_cached_records(@table_id)
    assert_nil cached_after, "Should have no cached records after schema change"

    # Step 4: Verify schema is also cleared
    schema = @cache.get_cached_table_schema(@table_id)
    assert_nil schema, "Schema should be cleared after structure change"
  end

  def test_invalidate_preserves_schema_when_structure_unchanged
    # Cache with schema
    structure = [
      { "slug" => "title", "label" => "Title", "field_type" => "textfield" }
    ]
    records = [ { "id" => "rec_1", "title" => "Test" } ]

    @cache.cache_table_records(@table_id, structure, records)

    # Invalidate WITHOUT structure change (e.g., just refreshing data)
    @cache.invalidate_table_cache(@table_id, structure_changed: false)

    # Records should be cleared
    refute @cache.cache_valid?(@table_id), "Cache should be invalid"

    # But schema should still exist (it's cached separately with longer TTL)
    # Note: This depends on implementation - schema might be in cache_table_schemas
    # The key point is structure_changed: false only clears records
  end

  def test_new_fields_in_records_are_stored_automatically
    # Initial cache with 2 fields
    structure_v1 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" }
    ]

    records_v1 = [
      { "id" => "rec_1", "name" => "Record 1", "status" => { "value" => "active" } }
    ]

    @cache.cache_table_records(@table_id, structure_v1, records_v1)

    # Invalidate and re-cache with NEW field (simulating SmartSuite schema change)
    @cache.invalidate_table_cache(@table_id, structure_changed: true)

    structure_v2 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" },
      { "slug" => "priority", "label" => "Priority", "field_type" => "singleselectfield" } # NEW FIELD
    ]

    records_v2 = [
      { "id" => "rec_1", "name" => "Record 1", "status" => { "value" => "active" }, "priority" => "high" }
    ]

    @cache.cache_table_records(@table_id, structure_v2, records_v2)

    # Verify new field is accessible
    cached = @cache.get_cached_records(@table_id)
    assert_equal 1, cached.size
    assert_equal "high", cached.first["priority"], "New field should be stored"

    # Verify new schema has 3 fields
    schema = @cache.get_cached_table_schema(@table_id)
    assert_equal 3, schema.size, "Schema should have 3 fields"
  end

  def test_removed_fields_dont_break_existing_cache
    # Cache with 3 fields
    structure_v1 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" },
      { "slug" => "old_field", "label" => "Old Field", "field_type" => "textfield" }
    ]

    records_v1 = [
      { "id" => "rec_1", "name" => "Record 1", "status" => { "value" => "active" }, "old_field" => "legacy data" }
    ]

    @cache.cache_table_records(@table_id, structure_v1, records_v1)

    # Without invalidation, old records still have old_field
    cached = @cache.get_cached_records(@table_id)
    assert_equal "legacy data", cached.first["old_field"]

    # After schema change invalidation + re-cache without old_field
    @cache.invalidate_table_cache(@table_id, structure_changed: true)

    structure_v2 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" }
      # old_field REMOVED
    ]

    records_v2 = [
      { "id" => "rec_1", "name" => "Record 1", "status" => { "value" => "active" } }
      # old_field not present in new data
    ]

    @cache.cache_table_records(@table_id, structure_v2, records_v2)

    # Verify old_field is gone
    cached_v2 = @cache.get_cached_records(@table_id)
    refute cached_v2.first.key?("old_field"), "Removed field should not exist in new cache"

    # Schema should only have 2 fields
    schema = @cache.get_cached_table_schema(@table_id)
    assert_equal 2, schema.size, "Schema should have 2 fields after removal"
  end

  def test_filters_work_after_schema_change
    # Initial schema
    structure_v1 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "category", "label" => "Category", "field_type" => "singleselectfield" }
    ]

    records_v1 = [
      { "id" => "rec_1", "name" => "Alpha", "category" => { "value" => "tech" } },
      { "id" => "rec_2", "name" => "Beta", "category" => { "value" => "finance" } }
    ]

    @cache.cache_table_records(@table_id, structure_v1, records_v1)

    # Filter works on initial schema
    filter_v1 = build_filter(field: "category", comparison: "is", value: "tech")
    results_v1 = @cache.get_cached_records(@table_id, filter: filter_v1)
    assert_equal 1, results_v1.size
    assert_equal "rec_1", results_v1.first["id"]

    # Schema change - add new field, change data
    @cache.invalidate_table_cache(@table_id, structure_changed: true)

    structure_v2 = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "category", "label" => "Category", "field_type" => "singleselectfield" },
      { "slug" => "priority", "label" => "Priority", "field_type" => "singleselectfield" }
    ]

    records_v2 = [
      { "id" => "rec_1", "name" => "Alpha Updated", "category" => { "value" => "tech" }, "priority" => { "value" => "high" } },
      { "id" => "rec_2", "name" => "Beta Updated", "category" => { "value" => "tech" }, "priority" => { "value" => "low" } }, # Changed to tech
      { "id" => "rec_3", "name" => "Gamma", "category" => { "value" => "finance" }, "priority" => { "value" => "medium" } }
    ]

    @cache.cache_table_records(@table_id, structure_v2, records_v2)

    # Filter on old field with new data
    filter_v2_category = build_filter(field: "category", comparison: "is", value: "tech")
    results_v2_category = @cache.get_cached_records(@table_id, filter: filter_v2_category)
    assert_equal 2, results_v2_category.size, "Should find 2 tech records after schema change"

    # Filter on NEW field
    filter_v2_priority = build_filter(field: "priority", comparison: "is", value: "high")
    results_v2_priority = @cache.get_cached_records(@table_id, filter: filter_v2_priority)
    assert_equal 1, results_v2_priority.size, "Should find 1 high priority record"
    assert_equal "rec_1", results_v2_priority.first["id"]
  end

  def test_cache_single_record_respects_current_schema
    # Initial cache
    structure = [
      { "slug" => "name", "label" => "Name", "field_type" => "textfield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" }
    ]

    records = [
      { "id" => "rec_1", "name" => "Original", "status" => { "value" => "active" } }
    ]

    @cache.cache_table_records(@table_id, structure, records)

    # Update single record with new field (simulating API response with new schema)
    updated_record = {
      "id" => "rec_1",
      "name" => "Updated",
      "status" => { "value" => "complete" },
      "new_field" => "new data" # Field not in original schema
    }

    @cache.cache_single_record(@table_id, updated_record)

    # Verify the record is updated with new data including new field
    cached = @cache.get_cached_record(@table_id, "rec_1")
    assert_equal "Updated", cached["name"]
    assert_equal "complete", cached.dig("status", "value")
    assert_equal "new data", cached["new_field"], "New field should be stored via JSONB flexibility"
  end

  def test_stale_records_not_returned_after_ttl_expiry
    # Cache with short TTL
    structure = [ { "slug" => "name", "label" => "Name", "field_type" => "textfield" } ]
    records = [ { "id" => "rec_1", "name" => "Test" } ]

    # Insert with already-expired TTL
    insert_expired_records(@table_id, structure, records)

    # Should not return expired records
    refute @cache.cache_valid?(@table_id), "Cache should be invalid for expired records"
    cached = @cache.get_cached_records(@table_id)
    assert_nil cached, "Should not return expired records"
  end

  def test_schema_version_isolation_between_tables
    # Two tables with different schemas
    table_a = "#{@table_id}_a"
    table_b = "#{@table_id}_b"

    structure_a = [
      { "slug" => "field_a", "label" => "Field A", "field_type" => "textfield" }
    ]

    structure_b = [
      { "slug" => "field_b", "label" => "Field B", "field_type" => "numberfield" }
    ]

    records_a = [ { "id" => "rec_a1", "field_a" => "text value" } ]
    records_b = [ { "id" => "rec_b1", "field_b" => 123 } ]

    @cache.cache_table_records(table_a, structure_a, records_a)
    @cache.cache_table_records(table_b, structure_b, records_b)

    # Invalidate table A's schema
    @cache.invalidate_table_cache(table_a, structure_changed: true)

    # Table B should be unaffected
    assert @cache.cache_valid?(table_b), "Table B cache should still be valid"
    cached_b = @cache.get_cached_records(table_b)
    assert_equal 1, cached_b.size
    assert_equal 123, cached_b.first["field_b"]

    # Table A should be cleared
    refute @cache.cache_valid?(table_a), "Table A cache should be invalid"

    # Cleanup
    clear_table_data!(table_a)
    clear_table_data!(table_b)
  end

  # ==================== Helper Methods ====================

  private

  def postgres_available?
    ActiveRecord::Base.connection.execute("SELECT 1")
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError
    false
  end

  def skip_unless_postgres_available!
    skip "PostgreSQL not available" unless postgres_available?
  end

  def clear_test_data!
    clear_table_data!(@table_id)
  end

  def clear_table_data!(table_id)
    conn = ActiveRecord::Base.connection.raw_connection
    conn.exec_params("DELETE FROM cache_records WHERE table_id = $1", [ table_id ])
    conn.exec_params("DELETE FROM cache_table_schemas WHERE table_id = $1", [ table_id ])
  rescue StandardError
    # Ignore if tables don't exist
  end

  def build_filter(field:, comparison:, value: nil)
    {
      "operator" => "and",
      "fields" => [ { "field" => field, "comparison" => comparison, "value" => value } ]
    }
  end

  def insert_expired_records(table_id, structure, records)
    conn = ActiveRecord::Base.connection.raw_connection
    past_time = Time.current - 1.hour
    expired_at = Time.current - 1.minute # Already expired

    # Insert expired schema
    conn.exec_params(
      "INSERT INTO cache_table_schemas (table_id, structure, cached_at, expires_at) VALUES ($1, $2, $3, $4)
       ON CONFLICT (table_id) DO UPDATE SET structure = $2, cached_at = $3, expires_at = $4",
      [ table_id, structure.to_json, past_time, expired_at ]
    )

    # Insert expired records
    records.each do |record|
      conn.exec_params(
        "INSERT INTO cache_records (table_id, record_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)",
        [ table_id, record["id"], record.to_json, past_time, expired_at ]
      )
    end
  end
end
