# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite/cache/metadata'
require_relative '../lib/smartsuite/cache/layer'
require 'sqlite3'
require 'fileutils'
require 'set'

class TestCacheMetadata < Minitest::Test
  def setup
    # Create a temporary database for testing
    @test_db_path = File.join(Dir.tmpdir, "test_cache_#{rand(100_000)}.db")
    @cache = SmartSuite::Cache::Layer.new(db_path: @test_db_path)
  end

  def teardown
    @cache.close
    FileUtils.rm_f(@test_db_path) if File.exist?(@test_db_path)
  end

  # Test map_field_type_to_sql for all 45+ field types
  def test_map_field_type_to_sql_text_fields
    text_types = %w[textfield textarea fullname email phonenumber address linkurl]

    text_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT"
    end
  end

  def test_map_field_type_to_sql_integer_fields
    integer_types = %w[autonumber comments_count]

    integer_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'INTEGER', result, "#{field_type} should map to INTEGER"
    end
  end

  def test_map_field_type_to_sql_real_fields
    real_types = %w[numberfield currencyfield percentfield ratingfield durationfield]

    real_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'REAL', result, "#{field_type} should map to REAL"
    end
  end

  def test_map_field_type_to_sql_boolean_fields
    result = @cache.send(:map_field_type_to_sql, 'yesnofield')
    assert_equal 'INTEGER', result, 'yesnofield should map to INTEGER (0/1)'
  end

  def test_map_field_type_to_sql_date_fields
    date_types = %w[datefield timefield]

    date_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT (ISO 8601)"
    end
  end

  def test_map_field_type_to_sql_select_fields
    select_types = %w[singleselectfield multipleselectfield tagfield]

    select_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT (JSON)"
    end
  end

  def test_map_field_type_to_sql_relationship_fields
    relationship_types = %w[linkedrecordfield assignedtofield]

    relationship_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT (JSON array)"
    end
  end

  def test_map_field_type_to_sql_file_fields
    file_types = %w[filesfield imagesfield signaturefield]

    file_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT (JSON array)"
    end
  end

  def test_map_field_type_to_sql_special_fields
    special_mappings = {
      'buttonfield' => 'TEXT',
      'emailfield' => 'TEXT',
      'phonefield' => 'TEXT',
      'linkfield' => 'TEXT',
      'ipaddressfield' => 'TEXT',
      'colorpickerfield' => 'TEXT',
      'socialnetworkfield' => 'TEXT'
    }

    special_mappings.each do |field_type, expected_sql_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal expected_sql_type, result, "#{field_type} should map to #{expected_sql_type}"
    end
  end

  def test_map_field_type_to_sql_unknown_field_type
    result = @cache.send(:map_field_type_to_sql, 'unknown_future_field_type')
    assert_equal 'TEXT', result, 'Unknown field types should default to TEXT'
  end

  # Test sanitize_table_name
  def test_sanitize_table_name_simple
    result = @cache.send(:sanitize_table_name, 'tbl_abc123def')
    assert_equal 'tbl_abc123def', result
  end

  def test_sanitize_table_name_with_hyphens
    result = @cache.send(:sanitize_table_name, 'tbl_abc-123-def')
    assert_equal 'tbl_abc_123_def', result, 'Hyphens should be converted to underscores'
  end

  def test_sanitize_table_name_with_spaces
    result = @cache.send(:sanitize_table_name, 'tbl abc 123')
    assert_equal 'tbl_abc_123', result, 'Spaces should be converted to underscores'
  end

  def test_sanitize_table_name_with_special_chars
    result = @cache.send(:sanitize_table_name, 'tbl@#$%123')
    assert_equal 'tbl____123', result, 'Special chars should be converted to underscores'
  end

  def test_sanitize_table_name_preserves_alphanumeric
    result = @cache.send(:sanitize_table_name, 'tbl_ABC123xyz')
    assert_equal 'tbl_ABC123xyz', result, 'Alphanumeric and underscores should be preserved'
  end

  # Test sanitize_column_name
  def test_sanitize_column_name_simple
    result = @cache.send(:sanitize_column_name, 's1a2b3c4d5')
    assert_equal 's1a2b3c4d5', result
  end

  def test_sanitize_column_name_lowercase
    result = @cache.send(:sanitize_column_name, 'FieldSlug')
    assert_equal 'fieldslug', result, 'Should be lowercased'
  end

  def test_sanitize_column_name_with_special_chars
    result = @cache.send(:sanitize_column_name, 'field-name@123')
    assert_equal 'field_name_123', result
  end

  def test_sanitize_column_name_with_spaces
    result = @cache.send(:sanitize_column_name, 'field name 123')
    assert_equal 'field_name_123', result
  end

  def test_sanitize_column_name_starts_with_number
    result = @cache.send(:sanitize_column_name, '123_field')
    assert_match(/^f_/, result, "Should prepend 'f_' if starts with number")
    assert_equal 'f_123_field', result
  end

  def test_sanitize_column_name_empty_after_sanitization
    result = @cache.send(:sanitize_column_name, '@#$%')
    assert_equal '____', result, 'Special chars converted to underscores'
  end

  # Test deduplicate_column_name
  def test_deduplicate_column_name_no_duplicates
    used_names = Set.new
    result = @cache.send(:deduplicate_column_name, 'status', used_names)
    assert_equal 'status', result, 'Should return original name if no conflicts'
  end

  def test_deduplicate_column_name_with_one_duplicate
    used_names = Set.new(['status'])
    result = @cache.send(:deduplicate_column_name, 'status', used_names)
    assert_equal 'status_2', result, 'Should append _2 for first duplicate'
  end

  def test_deduplicate_column_name_with_multiple_duplicates
    used_names = Set.new(%w[status status_2 status_3])
    result = @cache.send(:deduplicate_column_name, 'status', used_names)
    assert_equal 'status_4', result, 'Should find next available suffix'
  end

  def test_deduplicate_column_name_does_not_modify_set
    used_names = Set.new
    original_size = used_names.size
    @cache.send(:deduplicate_column_name, 'status', used_names)

    assert_equal original_size, used_names.size, 'Method should not modify used_names set'
  end

  # Test should_index_field?
  def test_should_index_field_status
    field = { 'field_type' => 'statusfield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Status fields should be indexed'
  end

  def test_should_index_field_single_select
    field = { 'field_type' => 'singleselectfield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Single select fields should be indexed'
  end

  def test_should_index_field_yesno
    field = { 'field_type' => 'yesnofield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Yes/no fields should be indexed'
  end

  def test_should_not_index_linked_record
    field = { 'field_type' => 'linkedrecordfield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    refute result, 'Linked record fields are not in always_index list'
  end

  def test_should_index_field_due_date
    field = { 'field_type' => 'duedatefield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Due date fields should be indexed'
  end

  def test_should_index_field_date_range
    field = { 'field_type' => 'daterangefield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Date range fields should be indexed'
  end

  def test_should_not_index_first_created
    field = { 'field_type' => 'firstcreated', 'slug' => 's36eb145e7' }
    result = @cache.send(:should_index_field?, field)
    refute result, 'First created is not in always_index list'
  end

  def test_should_index_field_system_last_updated
    field = { 'field_type' => 'lastupdated', 'slug' => 's5b629ed5f' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Last updated system field should be indexed'
  end

  def test_should_index_field_assigned_to
    field = { 'field_type' => 'assignedtofield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Assigned to fields should be indexed'
  end

  def test_should_index_field_currency
    field = { 'field_type' => 'currencyfield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Currency fields should be indexed'
  end

  def test_should_index_field_title
    field = { 'field_type' => 'textfield', 'slug' => 'title' }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Title field should be indexed'
  end

  def test_should_index_field_primary
    field = { 'field_type' => 'textfield', 'slug' => 's123', 'params' => { 'primary' => true } }
    result = @cache.send(:should_index_field?, field)
    assert result, 'Primary fields should be indexed'
  end

  def test_should_not_index_text_field
    field = { 'field_type' => 'textfield', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    refute result, 'Regular text fields should not be indexed'
  end

  def test_should_not_index_textarea
    field = { 'field_type' => 'textarea', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    refute result, 'Text area fields should not be indexed'
  end

  def test_should_not_index_formula
    field = { 'field_type' => 'formula', 'slug' => 's123' }
    result = @cache.send(:should_index_field?, field)
    refute result, 'Formula fields should not be indexed'
  end

  # Test get_table_ttl
  def test_get_table_ttl_default
    table_id = 'tbl_test_123'
    ttl = @cache.send(:get_table_ttl, table_id)

    # Should return default TTL (12 hours)
    assert_equal 12 * 3600, ttl
  end

  def test_get_table_ttl_custom
    table_id = 'tbl_test_456'

    # Set custom TTL
    @cache.send(:set_table_ttl, table_id, 7200, mutation_level: 'high_mutation', notes: 'Test table')

    ttl = @cache.send(:get_table_ttl, table_id)
    assert_equal 7200, ttl, 'Should return custom TTL'
  end

  # Test set_table_ttl
  def test_set_table_ttl
    table_id = 'tbl_test_789'
    custom_ttl = 3600

    @cache.send(:set_table_ttl, table_id, custom_ttl, mutation_level: 'high_mutation', notes: 'Frequently changing')

    # Verify it was stored
    ttl = @cache.send(:get_table_ttl, table_id)
    assert_equal custom_ttl, ttl
  end

  def test_set_table_ttl_with_preset
    table_id = 'tbl_test_preset'

    # Use a preset (low_mutation = 7 days)
    @cache.send(:set_table_ttl, table_id, SmartSuite::Cache::Layer::TTL_PRESETS[:low_mutation])

    ttl = @cache.send(:get_table_ttl, table_id)
    assert_equal 7 * 24 * 3600, ttl
  end

  # Test column name safety (SQL injection prevention)
  def test_sanitize_column_name_sql_injection_attempt
    malicious_inputs = [
      "'; DROP TABLE users; --",
      'id; DELETE FROM cache;',
      "col_name' OR '1'='1",
      'field`; UPDATE cache SET data=null;`'
    ]

    malicious_inputs.each do |input|
      result = @cache.send(:sanitize_column_name, input)

      # Should only contain safe characters
      assert_match(/^[a-z0-9_]+$/, result, 'Sanitized column name should only contain a-z, 0-9, underscore')
      refute_includes result, ';', 'Should not contain semicolon'
      refute_includes result, "'", 'Should not contain single quote'
      refute_includes result, '"', 'Should not contain double quote'
      refute_includes result, '-', 'Should not contain dash'
      refute_includes result, '`', 'Should not contain backtick'
    end
  end

  def test_sanitize_table_name_sql_injection_attempt
    malicious_inputs = [
      "'; DROP TABLE users; --",
      'tbl_123; DELETE FROM cache;',
      "table' OR '1'='1"
    ]

    malicious_inputs.each do |input|
      result = @cache.send(:sanitize_table_name, input)

      # Should only contain safe characters
      assert_match(/^[a-zA-Z0-9_]+$/, result, 'Sanitized table name should only contain alphanumeric and underscore')
      refute_includes result, ';'
      refute_includes result, "'"
    end
  end

  # Test field type mapping edge cases
  def test_map_field_type_to_sql_case_insensitive
    # Field types from API might have different casing
    result = @cache.send(:map_field_type_to_sql, 'TextField')
    assert_equal 'TEXT', result, 'Should handle mixed case field types'
  end

  def test_map_field_type_to_sql_with_nil
    result = @cache.send(:map_field_type_to_sql, nil)
    assert_equal 'TEXT', result, 'Nil field type should default to TEXT'
  end
end
