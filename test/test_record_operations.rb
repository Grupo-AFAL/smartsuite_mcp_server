# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite_client'
require 'webmock/minitest'
require 'stringio'

class TestRecordOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'

    # Disable real HTTP connections
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  # Test list_records requires table_id
  def test_list_records_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.list_records(nil, 10, 0, fields: ['status'])
    end

    assert_includes error.message, 'table_id', 'Should mention missing parameter'
  end

  # Test list_records requires fields parameter
  def test_list_records_requires_fields
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    result = client.list_records('tbl_123', 10, 0)

    assert result.is_a?(String), 'Should return string error message'
    assert_includes result, 'ERROR', 'Should indicate error'
    assert_includes result, 'fields', 'Should mention missing fields parameter'
  end

  # Test list_records with bypass_cache
  def test_list_records_bypass_cache
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Stub direct API call
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .to_return(
        status: 200,
        body: { items: [{ id: 'rec_1', status: 'active' }] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, fields: ['status'], bypass_cache: true)

    assert result.is_a?(String), 'Should return plain text'
  end

  # Test list_records with sort
  def test_list_records_with_sort
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including(
          'sort' => [{ 'field' => 'priority', 'direction' => 'desc' }]
        )
      )
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    sort = [{ 'field' => 'priority', 'direction' => 'desc' }]
    result = client.list_records('tbl_123', 10, 0, sort: sort, fields: ['priority'], bypass_cache: true)

    assert result.is_a?(String), 'Should return plain text'
  end

  # Test list_records with pagination
  def test_list_records_with_pagination
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=5&offset=10&hydrated=true')
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    result = client.list_records('tbl_123', 5, 10, fields: ['status'], bypass_cache: true)

    assert result.is_a?(String), 'Should handle pagination'
  end

  # Test get_record success
  def test_get_record_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { id: 'rec_456', title: 'Test Record' }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456')

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_456', result['id']
    assert_equal 'Test Record', result['title']
  end

  # Test get_record requires table_id
  def test_get_record_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.get_record(nil, 'rec_456')
    end

    assert_includes error.message, 'table_id'
  end

  # Test get_record requires record_id
  def test_get_record_requires_record_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.get_record('tbl_123', nil)
    end

    assert_includes error.message, 'record_id'
  end

  # Test create_record success
  def test_create_record_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    data = { 'title' => 'New Task', 'status' => 'Active' }

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/')
      .with(body: data.to_json)
      .to_return(
        status: 200,
        body: { id: 'rec_new', title: 'New Task', status: 'Active' }.to_json
      )

    result = client.create_record('tbl_123', data)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_new', result['id']
    assert_equal 'New Task', result['title']
  end

  # Test create_record requires table_id
  def test_create_record_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.create_record(nil, { 'title' => 'Test' })
    end

    assert_includes error.message, 'table_id'
  end

  # Test create_record requires data
  def test_create_record_requires_data
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.create_record('tbl_123', nil)
    end

    assert_includes error.message, 'data'
  end

  # Test create_record requires data to be hash
  def test_create_record_requires_data_hash
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.create_record('tbl_123', 'not a hash')
    end

    assert_includes error.message, 'data'
  end

  # Test update_record success
  def test_update_record_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    data = { 'status' => 'Completed' }

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .with(body: data.to_json)
      .to_return(
        status: 200,
        body: { id: 'rec_456', status: 'Completed' }.to_json
      )

    result = client.update_record('tbl_123', 'rec_456', data)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'Completed', result['status']
  end

  # Test update_record requires table_id
  def test_update_record_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.update_record(nil, 'rec_456', { 'status' => 'Done' })
    end

    assert_includes error.message, 'table_id'
  end

  # Test update_record requires record_id
  def test_update_record_requires_record_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.update_record('tbl_123', nil, { 'status' => 'Done' })
    end

    assert_includes error.message, 'record_id'
  end

  # Test update_record requires data
  def test_update_record_requires_data
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.update_record('tbl_123', 'rec_456', nil)
    end

    assert_includes error.message, 'data'
  end

  # Test update_record requires data to be hash
  def test_update_record_requires_data_hash
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.update_record('tbl_123', 'rec_456', 'not a hash')
    end

    assert_includes error.message, 'data'
  end

  # Test delete_record success
  def test_delete_record_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:delete, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { deleted: true }.to_json
      )

    result = client.delete_record('tbl_123', 'rec_456')

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal true, result['deleted']
  end

  # Test delete_record requires table_id
  def test_delete_record_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.delete_record(nil, 'rec_456')
    end

    assert_includes error.message, 'table_id'
  end

  # Test delete_record requires record_id
  def test_delete_record_requires_record_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.delete_record('tbl_123', nil)
    end

    assert_includes error.message, 'record_id'
  end

  # Test error handling for API failures
  def test_get_record_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(status: 404, body: { error: 'Not found' }.to_json)

    error = assert_raises(RuntimeError) do
      client.get_record('tbl_123', 'rec_456')
    end

    assert_includes error.message, '404'
  end

  # Test create_record API error
  def test_create_record_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/')
      .to_return(status: 400, body: { error: 'Bad request' }.to_json)

    error = assert_raises(RuntimeError) do
      client.create_record('tbl_123', { 'title' => 'Test' })
    end

    assert_includes error.message, '400'
  end

  # Test update_record API error
  def test_update_record_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(status: 500, body: 'Internal Server Error')

    error = assert_raises(RuntimeError) do
      client.update_record('tbl_123', 'rec_456', { 'status' => 'Done' })
    end

    assert_includes error.message, '500'
  end

  # Test delete_record API error
  def test_delete_record_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:delete, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(status: 403, body: { error: 'Forbidden' }.to_json)

    error = assert_raises(RuntimeError) do
      client.delete_record('tbl_123', 'rec_456')
    end

    assert_includes error.message, '403'
  end
end
