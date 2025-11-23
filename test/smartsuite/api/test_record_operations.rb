# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite_client'
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

  # ============================================================================
  # TEST HELPERS
  # ============================================================================

  # Creates a test client with cache disabled
  # @return [SmartSuiteClient] Client instance for testing
  def create_client
    SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
  end

  # Asserts that a method requires a specific parameter
  # @param method_name [Symbol] Method to test
  # @param param_name [String] Parameter name that should be required
  # @param args [Array] Arguments to pass to method (with nil for missing param)
  # @param kwargs [Hash] Keyword arguments to pass to method
  def assert_requires_parameter(method_name, param_name, *args, **kwargs)
    client = create_client
    error = assert_raises(ArgumentError) do
      if kwargs.empty?
        client.send(method_name, *args)
      else
        client.send(method_name, *args, **kwargs)
      end
    end
    assert_includes error.message, param_name
  end

  # Asserts that a method handles API errors correctly
  # @param method_name [Symbol] Method to test
  # @param endpoint [String] API endpoint URL
  # @param http_method [Symbol] HTTP method (:get, :post, :patch, :delete)
  # @param status_code [Integer] HTTP status code to simulate
  # @param args [Array] Arguments to pass to method
  # @param kwargs [Hash] Keyword arguments to pass to method
  def assert_api_error(method_name, endpoint, http_method, status_code, *args, **kwargs)
    client = create_client
    stub_request(http_method, endpoint)
      .to_return(status: status_code, body: { error: 'Error' }.to_json)
    error = assert_raises(RuntimeError) do
      if kwargs.empty?
        client.send(method_name, *args)
      else
        client.send(method_name, *args, **kwargs)
      end
    end
    assert_includes error.message, status_code.to_s
  end

  # ============================================================================
  # EXISTING TESTS
  # ============================================================================

  # Test list_records requires table_id
  def test_list_records_requires_table_id
    assert_requires_parameter(:list_records, 'table_id', nil, 10, 0, fields: ['status'])
  end

  # Test list_records requires fields parameter
  def test_list_records_requires_fields
    client = create_client
    result = client.list_records('tbl_123', 10, 0)

    assert result.is_a?(String), 'Should return string error message'
    assert_includes result, 'ERROR', 'Should indicate error'
    assert_includes result, 'fields', 'Should mention missing fields parameter'
  end

  # Test list_records with cache disabled
  def test_list_records_cache_disabled
    client = create_client

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
    client = create_client

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
    client = create_client

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
    client = create_client

    stub_request(:get, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { id: 'rec_456', title: 'Test Record' }.to_json
      )

    result = client.get_record('tbl_123', 'rec_456', format: :json)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_456', result['id']
    assert_equal 'Test Record', result['title']
  end

  # Test get_record requires table_id
  def test_get_record_requires_table_id
    assert_requires_parameter(:get_record, 'table_id', nil, 'rec_456')
  end

  # Test get_record requires record_id
  def test_get_record_requires_record_id
    assert_requires_parameter(:get_record, 'record_id', 'tbl_123', nil)
  end

  # Test create_record success
  def test_create_record_success
    client = create_client
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
    assert_requires_parameter(:create_record, 'table_id', nil, { 'title' => 'Test' })
  end

  # Test create_record requires data
  def test_create_record_requires_data
    assert_requires_parameter(:create_record, 'data', 'tbl_123', nil)
  end

  # Test create_record requires data to be hash
  def test_create_record_requires_data_hash
    assert_requires_parameter(:create_record, 'data', 'tbl_123', 'not a hash')
  end

  # Test update_record success
  def test_update_record_success
    client = create_client
    data = { 'status' => 'Completed' }

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .with(body: data.to_json)
      .to_return(
        status: 200,
        body: { id: 'rec_456', status: 'Completed' }.to_json
      )

    result = client.update_record('tbl_123', 'rec_456', data, minimal_response: false)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'Completed', result['status']
  end

  # Test update_record requires table_id
  def test_update_record_requires_table_id
    assert_requires_parameter(:update_record, 'table_id', nil, 'rec_456', { 'status' => 'Done' })
  end

  # Test update_record requires record_id
  def test_update_record_requires_record_id
    assert_requires_parameter(:update_record, 'record_id', 'tbl_123', nil, { 'status' => 'Done' })
  end

  # Test update_record requires data
  def test_update_record_requires_data
    assert_requires_parameter(:update_record, 'data', 'tbl_123', 'rec_456', nil)
  end

  # Test update_record requires data to be hash
  def test_update_record_requires_data_hash
    assert_requires_parameter(:update_record, 'data', 'tbl_123', 'rec_456', 'not a hash')
  end

  # Test delete_record success
  def test_delete_record_success
    client = create_client

    stub_request(:delete, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { deleted: true }.to_json
      )

    result = client.delete_record('tbl_123', 'rec_456', minimal_response: false)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal true, result['deleted']
  end

  # Test delete_record requires table_id
  def test_delete_record_requires_table_id
    assert_requires_parameter(:delete_record, 'table_id', nil, 'rec_456')
  end

  # Test delete_record requires record_id
  def test_delete_record_requires_record_id
    assert_requires_parameter(:delete_record, 'record_id', 'tbl_123', nil)
  end

  # Test error handling for API failures
  def test_get_record_api_error
    assert_api_error(
      :get_record,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/',
      :get,
      404,
      'tbl_123',
      'rec_456'
    )
  end

  # Test create_record API error
  def test_create_record_api_error
    assert_api_error(
      :create_record,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/',
      :post,
      400,
      'tbl_123',
      { 'title' => 'Test' }
    )
  end

  # Test update_record API error
  def test_update_record_api_error
    assert_api_error(
      :update_record,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/',
      :patch,
      500,
      'tbl_123',
      'rec_456',
      { 'status' => 'Done' }
    )
  end

  # Test delete_record API error
  def test_delete_record_api_error
    assert_api_error(
      :delete_record,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/',
      :delete,
      403,
      'tbl_123',
      'rec_456'
    )
  end

  # ============================================================================
  # REGRESSION TESTS: SmartDoc HTML Extraction
  # ============================================================================
  # Bug: SmartDoc fields (richtextarea) contain {data, html, preview, yjsData}
  # but AI only needs HTML. Previously returned all keys causing 60-70% extra tokens.
  # Fix: Extract only HTML content from SmartDoc fields while preserving full JSON in cache.

  # Test SmartDoc extraction from API response (Hash format)
  def test_get_record_extracts_smartdoc_html_from_api
    client = create_client

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

    result = client.get_record('tbl_123', 'rec_456', format: :json)

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
    client = create_client

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

    result = client.get_record('tbl_123', 'rec_456', format: :json)

    # Should return empty string, not nil
    assert_equal '', result['transcript'], 'Should return empty string for empty SmartDoc HTML'
  end

  # Test that non-SmartDoc Hash fields are not modified
  def test_get_record_preserves_non_smartdoc_json
    client = create_client

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

    result = client.get_record('tbl_123', 'rec_456', format: :json)

    # Should not be modified (not a SmartDoc structure)
    assert_equal regular_json, result['metadata'], 'Non-SmartDoc JSON should not be modified'
    assert result['metadata'].is_a?(Hash), 'Should still be a Hash'
  end

  # Test SmartDoc with multiple fields
  def test_get_record_extracts_multiple_smartdoc_fields
    client = create_client

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

    result = client.get_record('tbl_123', 'rec_456', format: :json)

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
    client = create_client

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
    client = create_client

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
    client = create_client

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
    client = create_client

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
    client = create_client
    records = [
      { 'title' => 'Task 1', 'status' => 'Active' },
      { 'title' => 'Task 2', 'status' => 'Pending' }
    ]

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .with(body: { 'items' => records }.to_json)
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
    assert_requires_parameter(:bulk_add_records, 'table_id', nil, [{ 'title' => 'Test' }])
  end

  # Test bulk_add_records requires records
  def test_bulk_add_records_requires_records
    assert_requires_parameter(:bulk_add_records, 'records', 'tbl_123', nil)
  end

  # Test bulk_add_records requires records to be array
  def test_bulk_add_records_requires_records_array
    assert_requires_parameter(:bulk_add_records, 'records', 'tbl_123', 'not an array')
  end

  # Test bulk_add_records API error
  def test_bulk_add_records_api_error
    assert_api_error(
      :bulk_add_records,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/',
      :post,
      400,
      'tbl_123',
      [{ 'title' => 'Test' }]
    )
  end

  # Test bulk_update_records success
  def test_bulk_update_records_success
    client = create_client
    records = [
      { 'id' => 'rec_1', 'status' => 'Completed' },
      { 'id' => 'rec_2', 'status' => 'In Progress' }
    ]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .with(body: { 'items' => records }.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', status: 'Completed' },
          { id: 'rec_2', status: 'In Progress' }
        ].to_json
      )

    result = client.bulk_update_records('tbl_123', records, minimal_response: false)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert_equal 'Completed', result[0]['status']
    assert_equal 'In Progress', result[1]['status']
  end

  # Test bulk_update_records requires table_id
  def test_bulk_update_records_requires_table_id
    assert_requires_parameter(:bulk_update_records, 'table_id', nil, [{ 'id' => 'rec_1', 'status' => 'Done' }])
  end

  # Test bulk_update_records requires records
  def test_bulk_update_records_requires_records
    assert_requires_parameter(:bulk_update_records, 'records', 'tbl_123', nil)
  end

  # Test bulk_update_records requires records to be array
  def test_bulk_update_records_requires_records_array
    assert_requires_parameter(:bulk_update_records, 'records', 'tbl_123', 'not an array')
  end

  # Test bulk_update_records API error
  def test_bulk_update_records_api_error
    assert_api_error(
      :bulk_update_records,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/',
      :patch,
      500,
      'tbl_123',
      [{ 'id' => 'rec_1', 'status' => 'Done' }]
    )
  end

  # Test bulk_delete_records success
  def test_bulk_delete_records_success
    client = create_client
    record_ids = %w[rec_1 rec_2 rec_3]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk_delete/')
      .with(body: { 'items' => record_ids }.to_json)
      .to_return(
        status: 200,
        body: { deleted: 3 }.to_json
      )

    result = client.bulk_delete_records('tbl_123', record_ids, minimal_response: false)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 3, result['deleted']
  end

  # Test bulk_delete_records requires table_id
  def test_bulk_delete_records_requires_table_id
    assert_requires_parameter(:bulk_delete_records, 'table_id', nil, ['rec_1'])
  end

  # Test bulk_delete_records requires record_ids
  def test_bulk_delete_records_requires_record_ids
    assert_requires_parameter(:bulk_delete_records, 'record_ids', 'tbl_123', nil)
  end

  # Test bulk_delete_records requires record_ids to be array
  def test_bulk_delete_records_requires_record_ids_array
    assert_requires_parameter(:bulk_delete_records, 'record_ids', 'tbl_123', 'not an array')
  end

  # Test bulk_delete_records API error
  def test_bulk_delete_records_api_error
    assert_api_error(
      :bulk_delete_records,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk_delete/',
      :patch,
      403,
      'tbl_123',
      ['rec_1']
    )
  end

  # ============================================================================
  # TESTS: File Operations
  # ============================================================================

  # Test get_file_url success
  def test_get_file_url_success
    client = create_client

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
    assert_requires_parameter(:get_file_url, 'file_handle', nil)
  end

  # Test get_file_url API error
  def test_get_file_url_api_error
    assert_api_error(
      :get_file_url,
      'https://app.smartsuite.com/api/v1/shared-files/handle_xyz/url/',
      :get,
      404,
      'handle_xyz'
    )
  end

  # ============================================================================
  # TESTS: Deleted Records Management
  # ============================================================================

  # Test list_deleted_records success with preview
  def test_list_deleted_records_success_with_preview
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=true')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Deleted Task 1', deleted_at: '2025-01-01T00:00:00Z' },
          { id: 'rec_2', title: 'Deleted Task 2', deleted_at: '2025-01-02T00:00:00Z' }
        ].to_json
      )

    result = client.list_deleted_records('sol_123', preview: true, format: :json)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert_equal 'rec_1', result[0]['id']
    assert_equal 'Deleted Task 1', result[0]['title']
  end

  # Test list_deleted_records success without preview
  def test_list_deleted_records_success_without_preview
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=false')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Deleted Task 1', deleted_at: '2025-01-01T00:00:00Z', all_fields: 'data' }
        ].to_json
      )

    result = client.list_deleted_records('sol_123', preview: false, format: :json)

    assert result.is_a?(Array), 'Should return array'
    assert_equal 1, result.length
    assert result[0].key?('all_fields'), 'Should include all fields when preview is false'
  end

  # Test list_deleted_records default preview value
  def test_list_deleted_records_default_preview
    client = create_client

    # Default preview should be true
    stub_request(:post, 'https://app.smartsuite.com/api/v1/deleted-records/?preview=true')
      .with(body: { solution_id: 'sol_123' }.to_json)
      .to_return(
        status: 200,
        body: [].to_json
      )

    result = client.list_deleted_records('sol_123', format: :json)

    assert result.is_a?(Array), 'Should return array'
  end

  # Test list_deleted_records requires solution_id
  def test_list_deleted_records_requires_solution_id
    assert_requires_parameter(:list_deleted_records, 'solution_id', nil)
  end

  # Test list_deleted_records API error
  def test_list_deleted_records_api_error
    assert_api_error(
      :list_deleted_records,
      'https://app.smartsuite.com/api/v1/deleted-records/?preview=true',
      :post,
      500,
      'sol_123'
    )
  end

  # Test restore_deleted_record success
  def test_restore_deleted_record_success
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/restore/')
      .with(body: {}.to_json)
      .to_return(
        status: 200,
        body: { id: 'rec_456', title: 'Task 1 (Restored)', status: 'Active' }.to_json
      )

    result = client.restore_deleted_record('tbl_123', 'rec_456', format: :json)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_456', result['id']
    assert_includes result['title'], '(Restored)', 'Title should include "(Restored)" suffix'
  end

  # Test restore_deleted_record requires table_id
  def test_restore_deleted_record_requires_table_id
    assert_requires_parameter(:restore_deleted_record, 'table_id', nil, 'rec_456')
  end

  # Test restore_deleted_record requires record_id
  def test_restore_deleted_record_requires_record_id
    assert_requires_parameter(:restore_deleted_record, 'record_id', 'tbl_123', nil)
  end

  # Test restore_deleted_record API error
  def test_restore_deleted_record_api_error
    assert_api_error(
      :restore_deleted_record,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/restore/',
      :post,
      404,
      'tbl_123',
      'rec_456'
    )
  end

  # ========================================================================
  # attach_file tests
  # ========================================================================

  # Test attach_file success
  def test_attach_file_success
    client = create_client

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .with(
        body: {
          'id' => 'rec_456',
          'attachments' => ['https://example.com/file.pdf', 'https://example.com/image.jpg']
        }.to_json
      )
      .to_return(
        status: 200,
        body: {
          'id' => 'rec_456',
          'title' => 'Test Record',
          'attachments' => [
            { 'url' => 'https://example.com/file.pdf', 'name' => 'file.pdf' },
            { 'url' => 'https://example.com/image.jpg', 'name' => 'image.jpg' }
          ]
        }.to_json
      )

    result = client.attach_file(
      'tbl_123',
      'rec_456',
      'attachments',
      ['https://example.com/file.pdf', 'https://example.com/image.jpg']
    )

    assert_equal true, result['success']
    assert_equal 'rec_456', result['record_id']
    assert_equal 2, result['attached_count']
    assert_equal 0, result['local_files']
    assert_equal 2, result['url_files']
    assert_equal 1, result['details'].length
    assert_equal 'url', result['details'][0]['type']
  end

  # Test attach_file requires table_id
  def test_attach_file_requires_table_id
    assert_requires_parameter(
      :attach_file,
      'table_id',
      nil,
      'rec_456',
      'attachments',
      ['https://example.com/file.pdf']
    )
  end

  # Test attach_file requires record_id
  def test_attach_file_requires_record_id
    assert_requires_parameter(
      :attach_file,
      'record_id',
      'tbl_123',
      nil,
      'attachments',
      ['https://example.com/file.pdf']
    )
  end

  # Test attach_file requires file_field_slug
  def test_attach_file_requires_file_field_slug
    assert_requires_parameter(
      :attach_file,
      'file_field_slug',
      'tbl_123',
      'rec_456',
      nil,
      ['https://example.com/file.pdf']
    )
  end

  # Test attach_file requires file_urls
  def test_attach_file_requires_file_urls
    assert_requires_parameter(
      :attach_file,
      'file_urls',
      'tbl_123',
      'rec_456',
      'attachments',
      nil
    )
  end

  # Test attach_file API error
  def test_attach_file_api_error
    assert_api_error(
      :attach_file,
      'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/',
      :patch,
      400,
      'tbl_123',
      'rec_456',
      'attachments',
      ['https://invalid-url']
    )
  end

  # Test attach_file detects URLs correctly
  def test_attach_file_url_detection
    client = create_client

    # Test url? method
    assert client.send(:url?, 'https://example.com/file.pdf')
    assert client.send(:url?, 'http://example.com/file.pdf')
    refute client.send(:url?, '/path/to/file.pdf')
    refute client.send(:url?, './relative/file.pdf')
    refute client.send(:url?, 'file.pdf')
  end

  # Test attach_file partitions files and URLs correctly
  def test_attach_file_partition_files_and_urls
    client = create_client

    inputs = [
      'https://example.com/image1.jpg',
      '/local/path/document.pdf',
      'http://cdn.example.com/file.zip',
      './relative/file.txt'
    ]

    local_files, urls = client.send(:partition_files_and_urls, inputs)

    assert_equal 2, urls.length
    assert_includes urls, 'https://example.com/image1.jpg'
    assert_includes urls, 'http://cdn.example.com/file.zip'

    assert_equal 2, local_files.length
    assert_includes local_files, '/local/path/document.pdf'
    assert_includes local_files, './relative/file.txt'
  end

  # Test attach_file with local files requires S3 configuration
  def test_attach_file_local_files_require_s3_config
    client = create_client

    # Ensure S3 env var is not set
    original_bucket = ENV.fetch('SMARTSUITE_S3_BUCKET', nil)
    ENV.delete('SMARTSUITE_S3_BUCKET')

    error = assert_raises(ArgumentError) do
      client.attach_file('tbl_123', 'rec_456', 'attachments', ['/local/file.pdf'])
    end

    assert_includes error.message, 'S3 configuration'
    assert_includes error.message, 'SMARTSUITE_S3_BUCKET'
  ensure
    ENV['SMARTSUITE_S3_BUCKET'] = original_bucket if original_bucket
  end

  # Test attach_file with only URLs works without S3
  def test_attach_file_urls_only_works_without_s3
    client = create_client

    # Ensure S3 env var is not set
    original_bucket = ENV.fetch('SMARTSUITE_S3_BUCKET', nil)
    ENV.delete('SMARTSUITE_S3_BUCKET')

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(status: 200, body: { 'id' => 'rec_456' }.to_json)

    # Should work fine with only URLs
    result = client.attach_file('tbl_123', 'rec_456', 'attachments', ['https://example.com/file.pdf'])
    assert_equal true, result['success']
    assert_equal 'rec_456', result['record_id']
    assert_equal 1, result['attached_count']
    assert_equal 0, result['local_files']
    assert_equal 1, result['url_files']
  ensure
    ENV['SMARTSUITE_S3_BUCKET'] = original_bucket if original_bucket
  end

  # ============================================================================
  # TESTS: Minimal Response Options
  # ============================================================================

  # Test create_record with minimal_response (default true)
  def test_create_record_minimal_response_default
    client = create_client
    data = { 'title' => 'New Task' }

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/')
      .to_return(
        status: 200,
        body: { id: 'rec_new', title: 'New Task', status: 'Active', many: 'fields' }.to_json
      )

    result = client.create_record('tbl_123', data)

    # Minimal response should only have key fields
    assert result.is_a?(Hash), 'Should return hash'
    assert result.key?('success'), 'Should have success key'
    assert result.key?('id'), 'Should have id key'
    assert_equal 'rec_new', result['id']
    refute result.key?('many'), 'Should not have extra fields'
  end

  # Test create_record with minimal_response: false
  def test_create_record_full_response
    client = create_client
    data = { 'title' => 'New Task' }

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/')
      .to_return(
        status: 200,
        body: { id: 'rec_new', title: 'New Task', status: 'Active', many: 'fields' }.to_json
      )

    result = client.create_record('tbl_123', data, minimal_response: false)

    # Full response should have all fields
    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 'rec_new', result['id']
    assert_equal 'New Task', result['title']
    assert_equal 'fields', result['many']
  end

  # Test update_record with minimal_response (default true)
  def test_update_record_minimal_response_default
    client = create_client
    data = { 'status' => 'Done' }

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { id: 'rec_456', title: 'Task', status: 'Done', extra: 'data' }.to_json
      )

    result = client.update_record('tbl_123', 'rec_456', data)

    # Minimal response by default
    assert result.is_a?(Hash), 'Should return hash'
    assert result.key?('success'), 'Should have success key'
    assert result.key?('id'), 'Should have id key'
    refute result.key?('extra'), 'Should not have extra fields'
  end

  # Test delete_record with minimal_response (default true)
  def test_delete_record_minimal_response_default
    client = create_client

    stub_request(:delete, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/rec_456/')
      .to_return(
        status: 200,
        body: { deleted: true, extra: 'info' }.to_json
      )

    result = client.delete_record('tbl_123', 'rec_456')

    # Minimal response by default
    assert result.is_a?(Hash), 'Should return hash'
    assert result.key?('success'), 'Should have success key'
    assert result.key?('id'), 'Should have id key'
  end

  # Test bulk_add_records with minimal_response
  def test_bulk_add_records_minimal_response
    client = create_client
    records = [{ 'title' => 'Task 1' }, { 'title' => 'Task 2' }]

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(
        status: 200,
        body: [
          { id: 'rec_1', title: 'Task 1', extra: 'data1' },
          { id: 'rec_2', title: 'Task 2', extra: 'data2' }
        ].to_json
      )

    result = client.bulk_add_records('tbl_123', records, minimal_response: true)

    # Minimal response
    assert result.is_a?(Array), 'Should return array'
    assert_equal 2, result.length
    assert result[0].key?('success'), 'Should have success key'
    refute result[0].key?('extra'), 'Should not have extra fields'
  end

  # Test bulk_update_records with minimal_response
  def test_bulk_update_records_minimal_response
    client = create_client
    records = [{ 'id' => 'rec_1', 'status' => 'Done' }]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(
        status: 200,
        body: [{ id: 'rec_1', status: 'Done', extra: 'data' }].to_json
      )

    result = client.bulk_update_records('tbl_123', records, minimal_response: true)

    # Minimal response
    assert result.is_a?(Array), 'Should return array'
    assert result[0].key?('success'), 'Should have success key'
  end

  # Test bulk_delete_records with minimal_response
  def test_bulk_delete_records_minimal_response
    client = create_client
    record_ids = %w[rec_1 rec_2]

    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk_delete/')
      .to_return(
        status: 200,
        body: { deleted: 2, extra: 'info' }.to_json
      )

    result = client.bulk_delete_records('tbl_123', record_ids, minimal_response: true)

    # Minimal response
    assert result.is_a?(Hash), 'Should return hash'
    assert result.key?('success'), 'Should have success key'
    assert result.key?('deleted_count'), 'Should have deleted_count'
  end

  # ============================================================================
  # TESTS: List Records With Hydrated Option
  # ============================================================================

  def test_list_records_with_hydrated_false
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0')
      .to_return(
        status: 200,
        body: { items: [{ id: 'rec_1', assigned_to: ['usr_123'] }] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, fields: ['assigned_to'], hydrated: false)

    assert result.is_a?(String), 'Should return plain text'
    assert_requested :post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0'
  end

  # ============================================================================
  # TESTS: List Records with filter (direct API)
  # ============================================================================

  def test_list_records_with_filter
    client = create_client

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' }
      ]
    }

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .with(
        body: hash_including('filter' => filter)
      )
      .to_return(
        status: 200,
        body: { items: [{ id: 'rec_1', status: 'Active' }] }.to_json
      )

    result = client.list_records('tbl_123', 10, 0, filter: filter, fields: ['status'])

    assert result.is_a?(String), 'Should return plain text'
  end

  # ============================================================================
  # TESTS: List Records with nil limit and offset (MCP edge case)
  # ============================================================================

  def test_list_records_with_nil_limit
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    # Called with nil limit (happens from MCP when parameter not provided)
    result = client.list_records('tbl_123', nil, 0, fields: ['status'])

    assert result.is_a?(String), 'Should handle nil limit'
  end

  def test_list_records_with_nil_offset
    client = create_client

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10&offset=0&hydrated=true')
      .to_return(
        status: 200,
        body: { items: [] }.to_json
      )

    # Called with nil offset
    result = client.list_records('tbl_123', 10, nil, fields: ['status'])

    assert result.is_a?(String), 'Should handle nil offset'
  end

  # ============================================================================
  # TESTS: List Records with empty fields array
  # ============================================================================

  def test_list_records_with_empty_fields_array
    client = create_client

    result = client.list_records('tbl_123', 10, 0, fields: [])

    assert result.is_a?(String), 'Should return string error message'
    assert_includes result, 'ERROR', 'Should indicate error for empty fields'
    assert_includes result, 'fields', 'Should mention fields parameter'
  end

  # ============================================================================
  # TESTS: parse_json_safe and smartdoc_value? helpers
  # ============================================================================

  def test_parse_json_safe_with_valid_json
    client = create_client

    result = client.parse_json_safe('{"key": "value"}')

    assert result.is_a?(Hash)
    assert_equal 'value', result['key']
  end

  def test_parse_json_safe_with_invalid_json
    client = create_client

    result = client.parse_json_safe('not valid json')

    assert_nil result, 'Should return nil for invalid JSON'
  end

  def test_parse_json_safe_with_nil
    client = create_client

    result = client.parse_json_safe(nil)

    assert_nil result, 'Should return nil for nil input'
  end

  def test_smartdoc_value_with_valid_smartdoc
    client = create_client

    smartdoc = {
      'data' => { 'type' => 'doc' },
      'html' => '<p>Content</p>'
    }

    result = client.smartdoc_value?(smartdoc)

    assert result, 'Should return true for valid SmartDoc'
  end

  def test_smartdoc_value_with_symbol_keys
    client = create_client

    smartdoc = {
      data: { type: 'doc' },
      html: '<p>Content</p>'
    }

    result = client.smartdoc_value?(smartdoc)

    assert result, 'Should return true for SmartDoc with symbol keys'
  end

  def test_smartdoc_value_without_data_key
    client = create_client

    not_smartdoc = { 'html' => '<p>Content</p>', 'preview' => 'Content' }

    result = client.smartdoc_value?(not_smartdoc)

    refute result, 'Should return false without data key'
  end

  def test_smartdoc_value_without_html_key
    client = create_client

    not_smartdoc = { 'data' => { 'type' => 'doc' }, 'preview' => 'Content' }

    result = client.smartdoc_value?(not_smartdoc)

    refute result, 'Should return false without html key'
  end

  def test_smartdoc_value_with_non_hash
    client = create_client

    assert_equal false, client.smartdoc_value?('string')
    assert_equal false, client.smartdoc_value?([1, 2, 3])
    assert_equal false, client.smartdoc_value?(nil)
    assert_equal false, client.smartdoc_value?(123)
  end

  # ============================================================================
  # TESTS: Bulk operations with unexpected response format
  # ============================================================================

  def test_bulk_add_records_with_non_array_response
    client = create_client
    records = [{ 'title' => 'Task 1' }]

    # API returns non-array response (unexpected)
    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(
        status: 200,
        body: { 'error' => 'unexpected format', 'partial' => true }.to_json
      )

    result = client.bulk_add_records('tbl_123', records, minimal_response: true)

    # Should return the response as-is (fallback)
    assert result.is_a?(Hash), 'Should return hash when response is not array'
    assert result.key?('error') || result.key?('partial'), 'Should return original response'
  end

  def test_bulk_add_records_full_response
    client = create_client
    records = [{ 'title' => 'Task 1' }]

    stub_request(:post, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(
        status: 200,
        body: [{ id: 'rec_1', title: 'Task 1', extra: 'data' }].to_json
      )

    result = client.bulk_add_records('tbl_123', records, minimal_response: false)

    # Full response - should include all fields
    assert result.is_a?(Array), 'Should return array'
    assert_equal 'rec_1', result[0]['id']
    assert_equal 'data', result[0]['extra'], 'Should include extra fields in full response'
  end

  def test_bulk_update_records_with_non_array_response
    client = create_client
    records = [{ 'id' => 'rec_1', 'status' => 'Done' }]

    # API returns non-array response (unexpected)
    stub_request(:patch, 'https://app.smartsuite.com/api/v1/applications/tbl_123/records/bulk/')
      .to_return(
        status: 200,
        body: { 'message' => 'partial success', 'errors' => [] }.to_json
      )

    result = client.bulk_update_records('tbl_123', records, minimal_response: true)

    # Should return the response as-is (fallback)
    assert result.is_a?(Hash), 'Should return hash when response is not array'
    assert result.key?('message'), 'Should return original response'
  end

  # ============================================================================
  # TESTS: Cache-enabled get_record (cache hit path)
  # ============================================================================

  def test_get_record_from_cache
    test_cache_path = File.join(Dir.tmpdir, "test_get_record_cache_#{rand(100_000)}.db")

    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: test_cache_path)

      # Setup: First need to populate the cache
      table_structure = {
        'id' => 'tbl_cache_get',
        'name' => 'Cache Test Table',
        'structure' => [
          { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
          { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'singleselectfield' }
        ]
      }

      records_response = {
        'items' => [
          { 'id' => 'rec_cached', 'title' => 'Cached Record', 'status' => 'Active' }
        ]
      }

      # Mock the table structure request
      stub_request(:get, %r{/applications/tbl_cache_get/})
        .to_return(status: 200, body: table_structure.to_json)

      # Mock the records list request (for cache population)
      stub_request(:post, %r{/applications/tbl_cache_get/records/list/})
        .to_return(status: 200, body: records_response.to_json)

      # First, populate cache by listing records
      client.list_records('tbl_cache_get', 10, 0, fields: %w[title status])

      # Now get_record should retrieve from cache (no API call)
      result = client.get_record('tbl_cache_get', 'rec_cached', format: :json)

      assert result.is_a?(Hash), 'Should return hash'
      assert_equal 'rec_cached', result['id']
      # The record should come from cache - no additional API request made
    ensure
      FileUtils.rm_f(test_cache_path)
    end
  end

  # ============================================================================
  # TESTS: Cache-enabled list_records with filter and sort
  # ============================================================================

  def test_list_records_from_cache_with_filter
    test_cache_path = File.join(Dir.tmpdir, "test_cache_filter_#{rand(100_000)}.db")

    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: test_cache_path)

      table_structure = {
        'id' => 'tbl_filter_test',
        'name' => 'Filter Test Table',
        'structure' => [
          { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
          { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'singleselectfield' }
        ]
      }

      records_response = {
        'items' => [
          { 'id' => 'rec_1', 'title' => 'Active Task', 'status' => 'Active' },
          { 'id' => 'rec_2', 'title' => 'Done Task', 'status' => 'Done' },
          { 'id' => 'rec_3', 'title' => 'Another Active', 'status' => 'Active' }
        ]
      }

      stub_request(:get, %r{/applications/tbl_filter_test/})
        .to_return(status: 200, body: table_structure.to_json)

      stub_request(:post, %r{/applications/tbl_filter_test/records/list/})
        .to_return(status: 200, body: records_response.to_json)

      filter = {
        'operator' => 'and',
        'fields' => [
          { 'field' => 'status', 'comparison' => 'is', 'value' => 'Active' }
        ]
      }

      result = client.list_records('tbl_filter_test', 10, 0, filter: filter, fields: %w[title status])

      assert result.is_a?(String), 'Should return plain text'
      # Filter should be applied to cached records
      assert_includes result, 'Active', 'Should include Active records'
    ensure
      FileUtils.rm_f(test_cache_path)
    end
  end

  def test_list_records_from_cache_with_sort
    test_cache_path = File.join(Dir.tmpdir, "test_cache_sort_#{rand(100_000)}.db")

    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: test_cache_path)

      table_structure = {
        'id' => 'tbl_sort_test',
        'name' => 'Sort Test Table',
        'structure' => [
          { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
          { 'slug' => 'priority', 'label' => 'Priority', 'field_type' => 'numberfield' }
        ]
      }

      records_response = {
        'items' => [
          { 'id' => 'rec_1', 'title' => 'Low Priority', 'priority' => 1 },
          { 'id' => 'rec_2', 'title' => 'High Priority', 'priority' => 5 },
          { 'id' => 'rec_3', 'title' => 'Medium Priority', 'priority' => 3 }
        ]
      }

      stub_request(:get, %r{/applications/tbl_sort_test/})
        .to_return(status: 200, body: table_structure.to_json)

      stub_request(:post, %r{/applications/tbl_sort_test/records/list/})
        .to_return(status: 200, body: records_response.to_json)

      # Sort by priority descending
      sort = [{ 'field' => 'priority', 'direction' => 'desc' }]

      result = client.list_records('tbl_sort_test', 10, 0, sort: sort, fields: %w[title priority])

      assert result.is_a?(String), 'Should return plain text'
      # Sort should be applied - highest priority first
      # The result is plain text, so just verify it executed
    ensure
      FileUtils.rm_f(test_cache_path)
    end
  end

  def test_list_records_from_cache_with_sort_symbol_keys
    test_cache_path = File.join(Dir.tmpdir, "test_cache_sort_sym_#{rand(100_000)}.db")

    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: test_cache_path)

      table_structure = {
        'id' => 'tbl_sort_sym',
        'name' => 'Sort Symbol Test',
        'structure' => [
          { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' }
        ]
      }

      records_response = { 'items' => [{ 'id' => 'rec_1', 'title' => 'Task' }] }

      stub_request(:get, %r{/applications/tbl_sort_sym/})
        .to_return(status: 200, body: table_structure.to_json)

      stub_request(:post, %r{/applications/tbl_sort_sym/records/list/})
        .to_return(status: 200, body: records_response.to_json)

      # Sort with symbol keys (covers lines 135-136)
      sort = [{ field: 'title', direction: 'asc' }]

      result = client.list_records('tbl_sort_sym', 10, 0, sort: sort, fields: ['title'])

      assert result.is_a?(String), 'Should handle symbol keys in sort'
    ensure
      FileUtils.rm_f(test_cache_path)
    end
  end

  # ============================================================================
  # TESTS: Cache-enabled record operations
  # ============================================================================

  def test_list_records_with_cache_enabled
    test_cache_path = File.join(Dir.tmpdir, "test_record_cache_#{rand(100_000)}.db")

    begin
      client = SmartSuiteClient.new(@api_key, @account_id, cache_path: test_cache_path)

      # First call - should fetch from API and cache
      # Need to mock get_table for structure and then records
      table_structure = {
        'id' => 'tbl_123',
        'name' => 'Test Table',
        'structure' => [
          { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
          { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'singleselectfield' }
        ]
      }

      records_response = {
        'items' => [
          { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'Active' },
          { 'id' => 'rec_2', 'title' => 'Task 2', 'status' => 'Done' }
        ]
      }

      stub_request(:get, %r{/applications/tbl_123/})
        .to_return(status: 200, body: table_structure.to_json)

      stub_request(:post, %r{/applications/tbl_123/records/list/})
        .to_return(status: 200, body: records_response.to_json)

      result = client.list_records('tbl_123', 10, 0, fields: %w[title status])

      assert result.is_a?(String), 'Should return plain text'
      assert_includes result, '2', 'Should include record count'
    ensure
      FileUtils.rm_f(test_cache_path)
    end
  end
end
