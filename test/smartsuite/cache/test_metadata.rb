# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite/cache/metadata'
require_relative '../../../lib/smartsuite/cache/layer'
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
    assert_equal 'column', result, 'Empty column name gets fallback value'
  end

  def test_sanitize_column_name_with_spanish_accents
    result = @cache.send(:sanitize_column_name, 'Título')
    assert_equal 'titulo', result, 'Spanish accents should be transliterated'
  end

  def test_sanitize_column_name_with_multiple_accents
    result = @cache.send(:sanitize_column_name, 'Última actualización')
    assert_equal 'ultima_actualizacion', result, 'Multiple accents should be handled'
  end

  def test_transliterate_accents_spanish
    result = @cache.send(:transliterate_accents, 'áéíóúñÁÉÍÓÚÑ')
    assert_equal 'aeiounAEIOUN', result, 'Spanish accents transliterated correctly'
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

  def test_map_field_type_to_sql_with_empty_string
    result = @cache.send(:map_field_type_to_sql, '')
    assert_equal 'TEXT', result, 'Empty field type should default to TEXT'
  end

  def test_map_field_type_to_sql_system_fields
    system_types = %w[record_id application_slug application_id followed_by]

    system_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'TEXT', result, "#{field_type} should map to TEXT"
    end
  end

  def test_map_field_type_to_sql_numberslider_and_percentcomplete
    slider_types = %w[numbersliderfield percentcompletefield]

    slider_types.each do |field_type|
      result = @cache.send(:map_field_type_to_sql, field_type)
      assert_equal 'REAL', result, "#{field_type} should map to REAL"
    end
  end

  # Test get_field_columns for multi-column field types
  def test_get_field_columns_status_field
    field = { 'slug' => 's123', 'label' => 'Status', 'field_type' => 'statusfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Status field should create 2 columns'
    assert result.key?('status'), 'Should have status column'
    assert result.key?('status_updated_on'), 'Should have status_updated_on column'
    assert_equal 'TEXT', result['status']
    assert_equal 'TEXT', result['status_updated_on']
  end

  def test_get_field_columns_date_field
    field = { 'slug' => 's123', 'label' => 'Event Date', 'field_type' => 'datefield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Date field should create 2 columns (date, include_time)'
    assert result.key?('event_date'), 'Should have date column'
    assert result.key?('event_date_include_time'), 'Should have include_time column'
    assert_equal 'TEXT', result['event_date']
    assert_equal 'INTEGER', result['event_date_include_time']
  end

  def test_get_field_columns_date_range_field
    field = { 'slug' => 's123', 'label' => 'Date Range', 'field_type' => 'daterangefield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 4, result.size, 'Date range should create 4 columns (from, from_include_time, to, to_include_time)'
    assert result.key?('date_range_from'), 'Should have from column'
    assert result.key?('date_range_from_include_time'), 'Should have from_include_time column'
    assert result.key?('date_range_to'), 'Should have to column'
    assert result.key?('date_range_to_include_time'), 'Should have to_include_time column'
  end

  def test_get_field_columns_due_date_field
    field = { 'slug' => 's123', 'label' => 'Due Date', 'field_type' => 'duedatefield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 6, result.size, 'Due date should create 6 columns (from, from_include_time, to, to_include_time, is_overdue, is_completed)'
    assert result.key?('due_date_from'), 'Should have from column'
    assert result.key?('due_date_from_include_time'), 'Should have from_include_time column'
    assert result.key?('due_date_to'), 'Should have to column'
    assert result.key?('due_date_to_include_time'), 'Should have to_include_time column'
    assert result.key?('due_date_is_overdue'), 'Should have is_overdue column'
    assert result.key?('due_date_is_completed'), 'Should have is_completed column'
  end

  def test_get_field_columns_address_field
    field = { 'slug' => 's123', 'label' => 'Address', 'field_type' => 'addressfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Address should create 2 columns'
    assert result.key?('address_text'), 'Should have text column'
    assert result.key?('address_json'), 'Should have json column'
  end

  def test_get_field_columns_full_name_field
    field = { 'slug' => 's123', 'label' => 'Name', 'field_type' => 'fullnamefield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Full name should create 2 columns'
    assert result.key?('name'), 'Should have name column'
    assert result.key?('name_json'), 'Should have json column'
  end

  def test_get_field_columns_smartdoc_field
    field = { 'slug' => 's123', 'label' => 'Description', 'field_type' => 'smartdocfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'SmartDoc should create 2 columns'
    assert result.key?('description_preview'), 'Should have preview column'
    assert result.key?('description_json'), 'Should have json column'
  end

  def test_get_field_columns_checklist_field
    field = { 'slug' => 's123', 'label' => 'Tasks', 'field_type' => 'checklistfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 3, result.size, 'Checklist should create 3 columns'
    assert result.key?('tasks_json'), 'Should have json column'
    assert result.key?('tasks_total'), 'Should have total column'
    assert result.key?('tasks_completed'), 'Should have completed column'
  end

  def test_get_field_columns_vote_field
    field = { 'slug' => 's123', 'label' => 'Votes', 'field_type' => 'votefield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Vote should create 2 columns'
    assert result.key?('votes_count'), 'Should have count column'
    assert result.key?('votes_json'), 'Should have json column'
  end

  def test_get_field_columns_time_tracking_field
    field = { 'slug' => 's123', 'label' => 'Time', 'field_type' => 'timetrackingfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Time tracking should create 2 columns'
    assert result.key?('time_json'), 'Should have json column'
    assert result.key?('time_total'), 'Should have total column'
    assert_equal 'REAL', result['time_total'], 'Total should be REAL'
  end

  def test_get_field_columns_first_created_field
    field = { 'slug' => 's123', 'label' => 'Created', 'field_type' => 'firstcreatedfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'First created should create 2 columns'
    assert result.key?('created_on'), 'Should have on column'
    assert result.key?('created_by'), 'Should have by column'
  end

  def test_get_field_columns_last_updated_field
    field = { 'slug' => 's123', 'label' => 'Updated', 'field_type' => 'lastupdatedfield' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Last updated should create 2 columns'
    assert result.key?('updated_on'), 'Should have on column'
    assert result.key?('updated_by'), 'Should have by column'
  end

  def test_get_field_columns_deleted_date_field
    field = { 'slug' => 's123', 'label' => 'Deleted', 'field_type' => 'deleted_date' }
    result = @cache.send(:get_field_columns, field)

    assert_equal 2, result.size, 'Deleted date should create 2 columns'
    assert result.key?('deleted_on'), 'Should have on column'
    assert result.key?('deleted_by'), 'Should have by column'
  end

  def test_get_field_columns_uses_slug_fallback_when_no_label
    field = { 'slug' => 's7a8b9c', 'label' => nil, 'field_type' => 'textfield' }
    result = @cache.send(:get_field_columns, field)

    assert result.key?('s7a8b9c'), 'Should use slug when label is nil'
  end

  def test_get_field_columns_uses_slug_fallback_when_empty_label
    field = { 'slug' => 's7a8b9c', 'label' => '', 'field_type' => 'textfield' }
    result = @cache.send(:get_field_columns, field)

    assert result.key?('s7a8b9c'), 'Should use slug when label is empty'
  end

  # Test create_cache_table creates actual table
  def test_create_cache_table_creates_table
    table_id = 'tbl_test_create'
    structure = {
      'name' => 'TestTable',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
        { 'slug' => 's123', 'label' => 'Status', 'field_type' => 'statusfield' }
      ]
    }

    sql_table_name = @cache.send(:create_cache_table, table_id, structure)

    # Verify table was created
    assert sql_table_name.include?('cache_records_'), 'Should return cache table name'
    assert sql_table_name.include?('TestTable'), 'Should include table name'

    # Verify schema was stored
    schema = @cache.send(:get_cached_table_schema, table_id)
    refute_nil schema, 'Schema should be stored'
    assert_equal sql_table_name, schema['sql_table_name']
    assert_equal 'TestTable', schema['table_name']
  end

  # Test get_or_create_cache_table returns existing table
  def test_get_or_create_cache_table_existing
    table_id = 'tbl_test_existing'
    structure = {
      'name' => 'Existing Table',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' }
      ]
    }

    # Create table first
    first_name = @cache.send(:get_or_create_cache_table, table_id, structure)

    # Call again - should return same name
    second_name = @cache.send(:get_or_create_cache_table, table_id, structure)

    assert_equal first_name, second_name, 'Should return same table name'
  end

  # Test handle_schema_evolution adds new fields
  def test_handle_schema_evolution_adds_fields
    table_id = 'tbl_test_evolution'
    initial_structure = {
      'name' => 'Evolving Table',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' }
      ]
    }

    # Create initial table
    @cache.send(:create_cache_table, table_id, initial_structure)

    # Add new field
    new_structure = {
      'name' => 'Evolving Table',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
        { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'singleselectfield' }
      ]
    }

    old_schema = @cache.send(:get_cached_table_schema, table_id)
    @cache.send(:handle_schema_evolution, table_id, new_structure, old_schema)

    # Verify new column was added
    updated_schema = @cache.send(:get_cached_table_schema, table_id)
    assert updated_schema['field_mapping'].key?('status'), 'Should have new status field'
  end

  # Test handle_schema_evolution with no new fields
  def test_handle_schema_evolution_no_changes
    table_id = 'tbl_test_no_change'
    structure = {
      'name' => 'Static Table',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' }
      ]
    }

    # Create initial table
    @cache.send(:create_cache_table, table_id, structure)
    old_schema = @cache.send(:get_cached_table_schema, table_id)
    old_updated_at = old_schema['updated_at']

    # Call with same structure - should not update
    @cache.send(:handle_schema_evolution, table_id, structure, old_schema)

    updated_schema = @cache.send(:get_cached_table_schema, table_id)
    assert_equal old_updated_at, updated_schema['updated_at'], 'Should not update timestamp when no changes'
  end

  # Test create_indexes_for_table creates indexes
  def test_create_indexes_for_table
    table_id = 'tbl_test_indexes'
    structure = {
      'name' => 'Index Table',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
        { 'slug' => 's_status', 'label' => 'Status', 'field_type' => 'statusfield' },
        { 'slug' => 's_due', 'label' => 'Due', 'field_type' => 'duedatefield' }
      ]
    }

    sql_table_name = @cache.send(:create_cache_table, table_id, structure)

    # Verify indexes exist by checking SQLite master table
    indexes = @cache.db.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?", [sql_table_name])
    index_names = indexes.map { |i| i['name'] }

    # Should have index for status field
    assert index_names.any? { |name| name.include?('status') }, 'Should have index for status field'
    # Should have index for expires_at
    assert index_names.any? { |name| name.include?('expires') }, 'Should have index for expires_at'
  end

  # Test sanitize_column_name handles reserved words
  def test_sanitize_column_name_reserved_words
    reserved_words = %w[table column index select insert update delete where from]

    reserved_words.each do |word|
      result = @cache.send(:sanitize_column_name, word)
      assert result.start_with?('field_'), "#{word} should be prefixed with field_"
    end
  end

  def test_sanitize_column_name_removes_consecutive_underscores
    result = @cache.send(:sanitize_column_name, 'field---name___test')
    refute result.include?('__'), 'Should not have consecutive underscores'
  end

  def test_sanitize_column_name_removes_leading_trailing_underscores
    result = @cache.send(:sanitize_column_name, '___field___')
    refute result.start_with?('_'), 'Should not start with underscore'
    refute result.end_with?('_'), 'Should not end with underscore'
  end

  # Test transliterate_accents with various European languages
  def test_transliterate_accents_french
    result = @cache.send(:transliterate_accents, 'café résumé')
    assert_equal 'cafe resume', result
  end

  def test_transliterate_accents_german
    # NOTE: Only ö→o and ü→u are transliterated, ß is not in the accent map
    result = @cache.send(:transliterate_accents, 'größe über')
    assert_equal 'große uber', result, 'Should transliterate ö and ü (ß is not in accent map)'
  end

  def test_transliterate_accents_portuguese
    result = @cache.send(:transliterate_accents, 'não ação')
    assert_equal 'nao acao', result
  end
end
