# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite_client'

class TestFieldOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @client = SmartSuiteClient.new(@api_key, @account_id)
  end

  # ========== add_field tests ==========

  def test_add_field_success
    table_id = 'tbl_123'
    field_data = {
      'slug' => 'priority_field',
      'label' => 'Priority',
      'field_type' => 'singleselectfield',
      'params' => {
        'choices' => [
          { 'label' => 'High', 'value' => 'uuid-1', 'value_color' => '#FF5757' },
          { 'label' => 'Low', 'value' => 'uuid-2', 'value_color' => '#54D62C' }
        ]
      }
    }

    expected_response = {
      'slug' => 'priority_field',
      'label' => 'Priority',
      'field_type' => 'singleselectfield'
    }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, body|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      captured_args[:body] = body
      expected_response
    end

    result = @client.add_field(table_id, field_data, format: :json)

    assert_equal :post, captured_args[:method]
    assert_equal '/applications/tbl_123/add_field/', captured_args[:endpoint]
    assert_equal field_data, captured_args[:body]['field']
    assert_equal({}, captured_args[:body]['field_position'])
    assert_equal true, captured_args[:body]['auto_fill_structure_layout']
    assert_equal 'priority_field', result['slug']
    assert_equal 'Priority', result['label']
  end

  def test_add_field_with_position
    table_id = 'tbl_123'
    field_data = { 'slug' => 'test', 'label' => 'Test', 'field_type' => 'textfield' }
    field_position = { 'prev_sibling_slug' => 'other_field' }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.add_field(table_id, field_data, field_position: field_position)

    assert_equal field_position, captured_body['field_position']
  end

  def test_add_field_without_auto_fill
    table_id = 'tbl_123'
    field_data = { 'slug' => 'test', 'label' => 'Test', 'field_type' => 'textfield' }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.add_field(table_id, field_data, auto_fill_structure_layout: false)

    assert_equal false, captured_body['auto_fill_structure_layout']
  end

  def test_add_field_missing_table_id
    field_data = { 'slug' => 'test', 'label' => 'Test', 'field_type' => 'textfield' }

    assert_raises(ArgumentError) do
      @client.add_field(nil, field_data)
    end

    assert_raises(ArgumentError) do
      @client.add_field('', field_data)
    end
  end

  def test_add_field_missing_field_data
    assert_raises(ArgumentError) do
      @client.add_field('tbl_123', nil)
    end
  end

  def test_add_field_invalid_field_data_type
    assert_raises(ArgumentError) do
      @client.add_field('tbl_123', 'not a hash')
    end
  end

  # ========== bulk_add_fields tests ==========

  def test_bulk_add_fields_success
    table_id = 'tbl_123'
    fields = [
      { 'slug' => 'field1', 'label' => 'Status', 'field_type' => 'statusfield', 'is_new' => true },
      { 'slug' => 'field2', 'label' => 'Priority', 'field_type' => 'singleselectfield', 'is_new' => true }
    ]

    expected_response = { 'status' => 'success' }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, body|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      captured_args[:body] = body
      expected_response
    end

    result = @client.bulk_add_fields(table_id, fields, format: :json)

    assert_equal :post, captured_args[:method]
    assert_equal '/applications/tbl_123/bulk-add-fields/', captured_args[:endpoint]
    # The API requires params field, so it's added automatically if missing
    expected_fields = fields.map { |f| f.merge('params' => {}) }
    assert_equal expected_fields, captured_args[:body]['fields']
    assert_equal 'success', result['status']
  end

  def test_bulk_add_fields_with_visible_reports
    table_id = 'tbl_123'
    fields = [{ 'slug' => 'field1', 'label' => 'Test', 'field_type' => 'textfield' }]
    report_ids = %w[report_1 report_2]

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.bulk_add_fields(table_id, fields, set_as_visible_fields_in_reports: report_ids)

    assert_equal report_ids, captured_body['set_as_visible_fields_in_reports']
  end

  def test_bulk_add_fields_missing_table_id
    fields = [{ 'slug' => 'field1', 'label' => 'Test', 'field_type' => 'textfield' }]

    assert_raises(ArgumentError) do
      @client.bulk_add_fields(nil, fields)
    end
  end

  def test_bulk_add_fields_missing_fields
    assert_raises(ArgumentError) do
      @client.bulk_add_fields('tbl_123', nil)
    end
  end

  def test_bulk_add_fields_invalid_fields_type
    assert_raises(ArgumentError) do
      @client.bulk_add_fields('tbl_123', 'not an array')
    end
  end

  # ========== update_field tests ==========

  def test_update_field_success
    table_id = 'tbl_123'
    slug = 'priority_field'
    field_data = {
      'label' => 'Updated Priority',
      'field_type' => 'singleselectfield',
      'params' => {
        'choices' => [
          { 'label' => 'Urgent', 'value' => 'uuid-1' },
          { 'label' => 'High', 'value' => 'uuid-2' },
          { 'label' => 'Low', 'value' => 'uuid-3' }
        ]
      }
    }

    expected_response = {
      'slug' => 'priority_field',
      'label' => 'Updated Priority',
      'field_type' => 'singleselectfield'
    }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, body|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      captured_args[:body] = body
      expected_response
    end

    result = @client.update_field(table_id, slug, field_data, format: :json)

    assert_equal :put, captured_args[:method]
    assert_equal '/applications/tbl_123/change_field/', captured_args[:endpoint]
    assert_equal slug, captured_args[:body]['slug']
    assert_equal 'Updated Priority', captured_args[:body]['label']
    assert_equal 'Updated Priority', result['label']
  end

  def test_update_field_merges_slug
    table_id = 'tbl_123'
    slug = 'my_field'
    field_data = { 'label' => 'New Label' }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.update_field(table_id, slug, field_data)

    # Verify slug is merged into body
    assert_equal 'my_field', captured_body['slug']
    assert_equal 'New Label', captured_body['label']
  end

  def test_update_field_adds_empty_params_when_not_provided
    table_id = 'tbl_123'
    slug = 'my_field'
    # field_data without params - API requires params to be present
    field_data = { 'label' => 'New Label', 'field_type' => 'textareafield' }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.update_field(table_id, slug, field_data)

    # Verify params is added as empty hash when not provided
    assert_equal({}, captured_body['params'])
    assert_equal 'New Label', captured_body['label']
  end

  def test_update_field_preserves_existing_params
    table_id = 'tbl_123'
    slug = 'my_field'
    field_data = { 'label' => 'New Label', 'params' => { 'required' => true } }

    captured_body = nil
    @client.define_singleton_method(:api_request) do |_method, _endpoint, body|
      captured_body = body
      {}
    end

    @client.update_field(table_id, slug, field_data)

    # Verify existing params are preserved
    assert_equal({ 'required' => true }, captured_body['params'])
  end

  def test_update_field_missing_table_id
    assert_raises(ArgumentError) do
      @client.update_field(nil, 'slug', { 'label' => 'Test' })
    end
  end

  def test_update_field_missing_slug
    assert_raises(ArgumentError) do
      @client.update_field('tbl_123', nil, { 'label' => 'Test' })
    end

    assert_raises(ArgumentError) do
      @client.update_field('tbl_123', '', { 'label' => 'Test' })
    end
  end

  def test_update_field_missing_field_data
    assert_raises(ArgumentError) do
      @client.update_field('tbl_123', 'slug', nil)
    end
  end

  def test_update_field_invalid_field_data_type
    assert_raises(ArgumentError) do
      @client.update_field('tbl_123', 'slug', 'not a hash')
    end
  end

  # ========== delete_field tests ==========

  def test_delete_field_success
    table_id = 'tbl_123'
    slug = 'field_to_delete'

    expected_response = {
      'slug' => 'field_to_delete',
      'label' => 'Deleted Field',
      'field_type' => 'textfield'
    }

    captured_args = {}
    @client.define_singleton_method(:api_request) do |method, endpoint, body|
      captured_args[:method] = method
      captured_args[:endpoint] = endpoint
      captured_args[:body] = body
      expected_response
    end

    result = @client.delete_field(table_id, slug, format: :json)

    assert_equal :post, captured_args[:method]
    assert_equal '/applications/tbl_123/delete_field/', captured_args[:endpoint]
    assert_equal slug, captured_args[:body]['slug']
    assert_equal 'field_to_delete', result['slug']
  end

  def test_delete_field_missing_table_id
    assert_raises(ArgumentError) do
      @client.delete_field(nil, 'slug')
    end

    assert_raises(ArgumentError) do
      @client.delete_field('', 'slug')
    end
  end

  def test_delete_field_missing_slug
    assert_raises(ArgumentError) do
      @client.delete_field('tbl_123', nil)
    end

    assert_raises(ArgumentError) do
      @client.delete_field('tbl_123', '')
    end
  end

  # ========== Cache invalidation tests ==========

  def test_add_field_invalidates_cache
    table_id = 'tbl_123'
    field_data = { 'slug' => 'test', 'label' => 'Test', 'field_type' => 'textfield' }
    invalidation_args = {}

    # Create a mock cache
    mock_cache = Object.new
    mock_cache.define_singleton_method(:invalidate_table_cache) do |tid, structure_changed:|
      invalidation_args[:table_id] = tid
      invalidation_args[:structure_changed] = structure_changed
    end

    @client.instance_variable_set(:@cache, mock_cache)
    @client.define_singleton_method(:api_request) { |_m, _e, _b| { 'slug' => 'test' } }

    @client.add_field(table_id, field_data)

    assert_equal table_id, invalidation_args[:table_id]
    assert_equal true, invalidation_args[:structure_changed]
  end

  def test_bulk_add_fields_invalidates_cache
    table_id = 'tbl_123'
    fields = [{ 'slug' => 'test', 'label' => 'Test', 'field_type' => 'textfield' }]
    invalidation_args = {}

    mock_cache = Object.new
    mock_cache.define_singleton_method(:invalidate_table_cache) do |tid, structure_changed:|
      invalidation_args[:table_id] = tid
      invalidation_args[:structure_changed] = structure_changed
    end

    @client.instance_variable_set(:@cache, mock_cache)
    @client.define_singleton_method(:api_request) { |_m, _e, _b| {} }

    @client.bulk_add_fields(table_id, fields)

    assert_equal table_id, invalidation_args[:table_id]
    assert_equal true, invalidation_args[:structure_changed]
  end

  def test_update_field_invalidates_cache
    table_id = 'tbl_123'
    invalidation_args = {}

    mock_cache = Object.new
    mock_cache.define_singleton_method(:invalidate_table_cache) do |tid, structure_changed:|
      invalidation_args[:table_id] = tid
      invalidation_args[:structure_changed] = structure_changed
    end

    @client.instance_variable_set(:@cache, mock_cache)
    @client.define_singleton_method(:api_request) { |_m, _e, _b| { 'slug' => 'test' } }

    @client.update_field(table_id, 'slug', { 'label' => 'New' })

    assert_equal table_id, invalidation_args[:table_id]
    assert_equal true, invalidation_args[:structure_changed]
  end

  def test_delete_field_invalidates_cache
    table_id = 'tbl_123'
    invalidation_args = {}

    mock_cache = Object.new
    mock_cache.define_singleton_method(:invalidate_table_cache) do |tid, structure_changed:|
      invalidation_args[:table_id] = tid
      invalidation_args[:structure_changed] = structure_changed
    end

    @client.instance_variable_set(:@cache, mock_cache)
    @client.define_singleton_method(:api_request) { |_m, _e, _b| { 'slug' => 'deleted' } }

    @client.delete_field(table_id, 'slug')

    assert_equal table_id, invalidation_args[:table_id]
    assert_equal true, invalidation_args[:structure_changed]
  end
end
