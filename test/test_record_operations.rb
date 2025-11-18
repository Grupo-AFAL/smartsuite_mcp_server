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

  # Test list_records with cache disabled
  def test_list_records_cache_disabled
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Stub direct API call
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .to_return(
        status: 200,
        body: { items: [{ id: 'rec_1', status: 'active' }] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, fields: ['status'])

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
    result = client.list_records('tbl_123', 10, 0, sort: sort, fields: ['priority'])

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

    result = client.list_records('tbl_123', 5, 10, fields: ['status'])

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

  # ============================================================================
  # REGRESSION TESTS: SmartDoc HTML Extraction
  # ============================================================================
  # Bug: SmartDoc fields (richtextarea) contain {data, html, preview, yjsData}
  # but AI only needs HTML. Previously returned all keys causing 60-70% extra tokens.
  # Fix: Extract only HTML content from SmartDoc fields while preserving full JSON in cache.

  # Test SmartDoc extraction from API response (Hash format)
  def test_get_record_extracts_smartdoc_html_from_api
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Mock API response with SmartDoc field as Hash
    smartdoc_field = {
      'data' => { 'type' => 'doc', 'content' => [] },
      'html' => '<div><h1>Meeting Notes</h1><p>Important discussion</p></div>',
      'preview' => 'Meeting Notes Important discussion',
      'yjsData' => 'base64encodeddata...'
    }

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: {
          id: 'rec_456',
          title: 'Test Record',
          description: smartdoc_field
        }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456')

    # Verify: description should be ONLY the HTML string
    assert_equal '<div><h1>Meeting Notes</h1><p>Important discussion</p></div>', result['description'],
                 'Should extract only HTML from SmartDoc field'

    # Verify: Not a Hash anymore
    refute result['description'].is_a?(Hash), 'Should not be a Hash'

    # Verify: Other fields unchanged
    assert_equal 'rec_456', result['id']
    assert_equal 'Test Record', result['title']
  end

  # Test SmartDoc extraction with empty HTML
  def test_get_record_extracts_smartdoc_empty_html
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    smartdoc_field = {
      'data' => { 'type' => 'doc', 'content' => [] },
      'html' => '',
      'preview' => '',
      'yjsData' => ''
    }

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: {
          id: 'rec_456',
          transcript: smartdoc_field
        }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456')

    # Should return empty string, not nil
    assert_equal '', result['transcript'], 'Should return empty string for empty SmartDoc HTML'
  end

  # Test that non-SmartDoc Hash fields are not modified
  def test_get_record_preserves_non_smartdoc_json
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Regular JSON object that has "html" key but not SmartDoc structure (missing "data" key)
    regular_json = { 'html' => 'value', 'other' => 'data' }

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: {
          id: 'rec_456',
          metadata: regular_json
        }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456')

    # Should not be modified (not a SmartDoc structure)
    assert_equal regular_json, result['metadata'], 'Non-SmartDoc JSON should not be modified'
    assert result['metadata'].is_a?(Hash), 'Should still be a Hash'
  end

  # Test SmartDoc with multiple fields
  def test_get_record_extracts_multiple_smartdoc_fields
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    smartdoc1 = {
      'data' => { 'type' => 'doc' },
      'html' => '<p>Description content</p>',
      'preview' => 'Description content',
      'yjsData' => 'data1'
    }

    smartdoc2 = {
      'data' => { 'type' => 'doc' },
      'html' => '<p>Notes content</p>',
      'preview' => 'Notes content',
      'yjsData' => 'data2'
    }

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: {
          id: 'rec_456',
          title: 'Regular field',
          description: smartdoc1,
          notes: smartdoc2
        }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456')

    # Both SmartDoc fields should be extracted
    assert_equal '<p>Description content</p>', result['description']
    assert_equal '<p>Notes content</p>', result['notes']

    # Regular field unchanged
    assert_equal 'Regular field', result['title']
  end

  # ============================================================================
  # REGRESSION TESTS: Filter Sanitization for API
  # ============================================================================
  # Bug: SmartSuite API rejects is_empty/is_not_empty filters with empty string value
  # Error: "' is not allowed for the 'is_not_empty' comparison"
  # Fix: Sanitize filters before sending to API - set value to null for empty check operators

  # Test is_not_empty filter is sanitized to null value
  def test_list_records_sanitizes_is_not_empty_filter
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is_not_empty', 'value' => '' }
      ]
    }

    # Verify API receives sanitized filter with null value
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including(
          'filter' => hash_including(
            'fields' => [
              hash_including('field' => 'status', 'comparison' => 'is_not_empty', 'value' => nil)
            ]
          )
        )
      )
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, filter: filter, fields: ['status'])

    assert result.is_a?(String), 'Should return plain text'
  end

  # Test is_empty filter is sanitized to null value
  def test_list_records_sanitizes_is_empty_filter
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'assigned_to', 'comparison' => 'is_empty', 'value' => '' }
      ]
    }

    # Verify API receives sanitized filter with null value
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including(
          'filter' => hash_including(
            'fields' => [
              hash_including('field' => 'assigned_to', 'comparison' => 'is_empty', 'value' => nil)
            ]
          )
        )
      )
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, filter: filter, fields: ['assigned_to'])

    assert result.is_a?(String), 'Should return plain text'
  end

  # Test multiple filter fields with mixed operators
  def test_list_records_sanitizes_mixed_filter_operators
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' },
        { 'field' => 'priority', 'comparison' => 'is_not_empty', 'value' => '' },
        { 'field' => 'notes', 'comparison' => 'is_empty', 'value' => 'should_be_null' }
      ]
    }

    # Verify only empty check operators are sanitized
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including(
          'filter' => hash_including(
            'fields' => [
              hash_including('field' => 'status', 'comparison' => 'is', 'value' => 'Active'),
              hash_including('field' => 'priority', 'comparison' => 'is_not_empty', 'value' => nil),
              hash_including('field' => 'notes', 'comparison' => 'is_empty', 'value' => nil)
            ]
          )
        )
      )
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, filter: filter, fields: %w[status priority notes])

    assert result.is_a?(String), 'Should return plain text'
  end

  # Test non-empty-check operators are not modified
  def test_list_records_preserves_other_filter_operators
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'title', 'comparison' => 'contains', 'value' => 'test' },
        { 'field' => 'amount', 'comparison' => 'is_greater_than', 'value' => 100 }
      ]
    }

    # Verify other operators keep their values
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including(
          'filter' => hash_including(
            'fields' => [
              hash_including('field' => 'title', 'comparison' => 'contains', 'value' => 'test'),
              hash_including('field' => 'amount', 'comparison' => 'is_greater_than', 'value' => 100)
            ]
          )
        )
      )
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, filter: filter, fields: %w[title amount])

    assert result.is_a?(String), 'Should return plain text'
  end

  # ============================================================================
  # TESTS: Bulk Operations
  # ============================================================================

  # Test bulk_add_records success
  def test_bulk_add_records_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    records = [
      { 'title' => 'Task 1', 'status' => 'Active' },
      { 'title' => 'Task 2', 'status' => 'Pending' }
    ]

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .with(body: records.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Task 1', status: 'Active' },
          { id: 'rec_2', title: 'Task 2', status: 'Pending' }
        ].to_json
      )

    result = client.bulk_add_records('tbl_123', records)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert_equal 'rec_1', result[0]['id']
    assert_equal 'rec_2', result[1]['id']
  end

  # Test bulk_add_records requires table_id
  def test_bulk_add_records_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_add_records(nil, [{ 'title' => 'Test' }])
    end

    assert_includes error.message, 'table_id'
  end

  # Test bulk_add_records requires records
  def test_bulk_add_records_requires_records
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_add_records('tbl_123', nil)
    end

    assert_includes error.message, 'records'
  end

  # Test bulk_add_records requires records to be array
  def test_bulk_add_records_requires_records_array
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_add_records('tbl_123', 'not an array')
    end

    assert_includes error.message, 'records'
  end

  # Test bulk_add_records API error
  def test_bulk_add_records_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(status: 400, body: { error: 'Bad request' }.to_json)

    error = assert_raises(RuntimeError) do
      client.bulk_add_records('tbl_123', [{ 'title' => 'Test' }])
    end

    assert_includes error.message, '400'
  end

  # Test bulk_update_records success
  def test_bulk_update_records_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    records = [
      { 'id' => 'rec_1', 'status' => 'Completed' },
      { 'id' => 'rec_2', 'status' => 'In Progress' }
    ]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .with(body: records.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', status: 'Completed' },
          { id: 'rec_2', status: 'In Progress' }
        ].to_json
      )

    result = client.bulk_update_records('tbl_123', records)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert_equal 'Completed', result[0]['status']
    assert_equal 'In Progress', result[1]['status']
  end

  # Test bulk_update_records requires table_id
  def test_bulk_update_records_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_update_records(nil, [{ 'id' => 'rec_1', 'status' => 'Done' }])
    end

    assert_includes error.message, 'table_id'
  end

  # Test bulk_update_records requires records
  def test_bulk_update_records_requires_records
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_update_records('tbl_123', nil)
    end

    assert_includes error.message, 'records'
  end

  # Test bulk_update_records requires records to be array
  def test_bulk_update_records_requires_records_array
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_update_records('tbl_123', 'not an array')
    end

    assert_includes error.message, 'records'
  end

  # Test bulk_update_records API error
  def test_bulk_update_records_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(status: 500, body: 'Internal Server Error')

    error = assert_raises(RuntimeError) do
      client.bulk_update_records('tbl_123', [{ 'id' => 'rec_1', 'status' => 'Done' }])
    end

    assert_includes error.message, '500'
  end

  # Test bulk_delete_records success
  def test_bulk_delete_records_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    record_ids = %w[rec_1 rec_2 rec_3]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk_delete/')
      .with(body: record_ids.to_json)
      .to_return(
        status: 200,
        body: { deleted: 3 }.to_json
      )

    result = client.bulk_delete_records('tbl_123', record_ids)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 3, result['deleted']
  end

  # Test bulk_delete_records requires table_id
  def test_bulk_delete_records_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_delete_records(nil, ['rec_1'])
    end

    assert_includes error.message, 'table_id'
  end

  # Test bulk_delete_records requires record_ids
  def test_bulk_delete_records_requires_record_ids
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_delete_records('tbl_123', nil)
    end

    assert_includes error.message, 'record_ids'
  end

  # Test bulk_delete_records requires record_ids to be array
  def test_bulk_delete_records_requires_record_ids_array
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.bulk_delete_records('tbl_123', 'not an array')
    end

    assert_includes error.message, 'record_ids'
  end

  # Test bulk_delete_records API error
  def test_bulk_delete_records_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk_delete/')
      .to_return(status: 403, body: { error: 'Forbidden' }.to_json)

    error = assert_raises(RuntimeError) do
      client.bulk_delete_records('tbl_123', ['rec_1'])
    end

    assert_includes error.message, '403'
  end

  # ============================================================================
  # TESTS: File Operations
  # ============================================================================

  # Test get_file_url success
  def test_get_file_url_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:get, 'https://app.smartsuite.com/api/v1/shared-files/handle_xyz/url/')
      .to_return(
        status: 200,
        body: { url: 'https://files.smartsuite.com/file/123/document.pdf' }.to_json
      )

    result = client.get_file_url('handle_xyz')

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'https://files.smartsuite.com/file/123/document.pdf', result['url']
  end

  # Test get_file_url requires file_handle
  def test_get_file_url_requires_file_handle
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.get_file_url(nil)
    end

    assert_includes error.message, 'file_handle'
  end

  # Test get_file_url API error
  def test_get_file_url_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:get, 'https://app.smartsuite.com/api/v1/shared-files/handle_xyz/url/')
      .to_return(status: 404, body: { error: 'File not found' }.to_json)

    error = assert_raises(RuntimeError) do
      client.get_file_url('handle_xyz')
    end

    assert_includes error.message, '404'
  end

  # ============================================================================
  # TESTS: Deleted Records Management
  # ============================================================================

  # Test list_deleted_records success with preview
  def test_list_deleted_records_success_with_preview
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=true')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Deleted Task 1', deleted_at: '2025-01-01T00:00:00Z' },
          { id: 'rec_2', title: 'Deleted Task 2', deleted_at: '2025-01-02T00:00:00Z' }
        ].to_json
      )

    result = client.list_deleted_records('sol_123', preview: true)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert_equal 'rec_1', result[0]['id']
    assert_equal 'Deleted Task 1', result[0]['title']
  end

  # Test list_deleted_records success without preview
  def test_list_deleted_records_success_without_preview
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=false')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Deleted Task 1', deleted_at: '2025-01-01T00:00:00Z', all_fields: 'data' }
        ].to_json
      )

    result = client.list_deleted_records('sol_123', preview: false)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 1, result.length
    assert result[0].key?('all_fields'), 'Should include all fields when preview is false'
  end

  # Test list_deleted_records default preview value
  def test_list_deleted_records_default_preview
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Default preview should be true
    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=true')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [].to_json
      )

    result = client.list_deleted_records('sol_123')

    assert result.is_a?(Array), 'Should return array'
  end

  # Test list_deleted_records requires solution_id
  def test_list_deleted_records_requires_solution_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.list_deleted_records(nil)
    end

    assert_includes error.message, 'solution_id'
  end

  # Test list_deleted_records API error
  def test_list_deleted_records_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=true')
      .to_return(status: 500, body: 'Internal Server Error')

    error = assert_raises(RuntimeError) do
      client.list_deleted_records('sol_123')
    end

    assert_includes error.message, '500'
  end

  # Test restore_deleted_record success
  def test_restore_deleted_record_success
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/restore/')
      .with(body: {}.to_json)
      .to_return(
        status: 200,
        body: { id: 'rec_456', title: 'Task 1 (Restored)', status: 'Active' }.to_json
      )

    result = client.restore_deleted_record('tbl_123', 'rec_456')

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_456', result['id']
    assert_includes result['title'], '(Restored)', 'Title should include "(Restored)" suffix'
  end

  # Test restore_deleted_record requires table_id
  def test_restore_deleted_record_requires_table_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.restore_deleted_record(nil, 'rec_456')
    end

    assert_includes error.message, 'table_id'
  end

  # Test restore_deleted_record requires record_id
  def test_restore_deleted_record_requires_record_id
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    error = assert_raises(ArgumentError) do
      client.restore_deleted_record('tbl_123', nil)
    end

    assert_includes error.message, 'record_id'
  end

  # Test restore_deleted_record API error
  def test_restore_deleted_record_api_error
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/restore/')
      .to_return(status: 404, body: { error: 'Record not found' }.to_json)

    error = assert_raises(RuntimeError) do
      client.restore_deleted_record('tbl_123', 'rec_456')
    end

    assert_includes error.message, '404'
  end
end
