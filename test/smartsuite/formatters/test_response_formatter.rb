# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite/formatters/response_formatter'
require 'json'

class TestResponseFormatter < Minitest::Test
  # Include the module to test
  include SmartSuite::Formatters::ResponseFormatter

  # Mock log_metric and log_token_usage methods since they're used but not in this module
  def log_metric(_message)
    # Silently ignore logging in tests
  end

  def log_token_usage(_tokens)
    # Silently ignore logging in tests
  end

  # Test filter_field_structure with full field data
  def test_filter_field_structure_basic
    field = {
      'slug' => 'title',
      'label' => 'Task Title',
      'field_type' => 'textfield',
      'params' => {
        'required' => true,
        'unique' => false,
        'display_format' => 'default', # Should be filtered out
        'width' => 200 # Should be filtered out
      }
    }

    result = filter_field_structure(field)

    assert_equal 'title', result['slug']
    assert_equal 'Task Title', result['label']
    assert_equal 'textfield', result['field_type']
    assert_equal true, result['params']['required']
    assert_equal false, result['params']['unique']
    refute result['params'].key?('display_format'), 'Should not include display_format'
    refute result['params'].key?('width'), 'Should not include width'
  end

  # Test filter_field_structure with primary field
  def test_filter_field_structure_primary
    field = {
      'slug' => 'id',
      'label' => 'ID',
      'field_type' => 'recordidfield',
      'params' => {
        'primary' => true
      }
    }

    result = filter_field_structure(field)

    assert_equal true, result['params']['primary']
  end

  # Test filter_field_structure with choices (status/select fields)
  def test_filter_field_structure_with_choices
    field = {
      'slug' => 'status',
      'label' => 'Status',
      'field_type' => 'statusfield',
      'params' => {
        'choices' => [
          {
            'label' => 'Active',
            'value' => 'active',
            'color' => '#00FF00', # Should be filtered out
            'icon' => 'check' # Should be filtered out
          },
          {
            'label' => 'Inactive',
            'value' => 'inactive',
            'color' => '#FF0000',
            'icon' => 'x'
          }
        ]
      }
    }

    result = filter_field_structure(field)

    assert_equal 2, result['params']['choices'].size
    assert_equal 'Active', result['params']['choices'][0]['label']
    assert_equal 'active', result['params']['choices'][0]['value']
    refute result['params']['choices'][0].key?('color'), 'Should not include color'
    refute result['params']['choices'][0].key?('icon'), 'Should not include icon'
  end

  # Test filter_field_structure with linked record field
  def test_filter_field_structure_with_linked_record
    field = {
      'slug' => 'project',
      'label' => 'Related Project',
      'field_type' => 'linkedrecordfield',
      'params' => {
        'linked_application' => 'tbl_projects',
        'entries_allowed' => 'multiple',
        'visible_fields' => %w[name status] # Should be filtered out
      }
    }

    result = filter_field_structure(field)

    assert_equal 'tbl_projects', result['params']['linked_application']
    assert_equal 'multiple', result['params']['entries_allowed']
    refute result['params'].key?('visible_fields'), 'Should not include visible_fields'
  end

  # Test filter_field_structure without params
  def test_filter_field_structure_no_params
    field = {
      'slug' => 'name',
      'label' => 'Name',
      'field_type' => 'textfield'
    }

    result = filter_field_structure(field)

    assert_equal 'name', result['slug']
    assert_equal 'Name', result['label']
    assert_equal 'textfield', result['field_type']
    refute result.key?('params'), 'Should not include empty params'
  end

  # Test filter_records_response with JSON format
  def test_filter_records_response_json_format
    response = {
      'items' => [
        { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'active', 'priority' => 1 },
        { 'id' => 'rec_2', 'title' => 'Task 2', 'status' => 'pending', 'priority' => 2 }
      ],
      'total_count' => 2
    }

    result = filter_records_response(response, ['status'], plain_text: false)

    assert result.is_a?(Hash), 'Should return hash in JSON format'
    assert_equal 2, result['count']
    assert_equal 2, result['total_count']
    assert_equal 2, result['items'].size

    # Should include requested fields + id + title
    assert result['items'][0].key?('id')
    assert result['items'][0].key?('title')
    assert result['items'][0].key?('status')
    refute result['items'][0].key?('priority'), 'Should not include unrequested fields'
  end

  # Test filter_records_response with plain text format
  def test_filter_records_response_plain_text
    response = {
      'items' => [
        { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'active' }
      ],
      'total_count' => 1
    }

    result = filter_records_response(response, ['status'], plain_text: true)

    assert result.is_a?(String), 'Should return string in plain text format'
    assert_includes result, 'rec_1'
    assert_includes result, 'Task 1'
    assert_includes result, 'active'
    assert_includes result, '1 of 1 total'
  end

  # Test filter_records_response with filtered count
  def test_filter_records_response_with_filtered_count
    response = {
      'items' => [
        { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'active' }
      ],
      'total_count' => 100,
      'filtered_count' => 50
    }

    result = filter_records_response(response, ['status'], plain_text: true)

    assert_includes result, '50 filtered'
    assert_includes result, '100 total'
  end

  # Test filter_records_response with no fields specified
  def test_filter_records_response_no_fields
    response = {
      'items' => [
        { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'active', 'priority' => 1 }
      ],
      'total_count' => 1
    }

    result = filter_records_response(response, nil, plain_text: false)

    # Should only include id and title when no fields specified
    assert result['items'][0].key?('id')
    assert result['items'][0].key?('title')
    refute result['items'][0].key?('status'), 'Should not include unrequested fields'
    refute result['items'][0].key?('priority'), 'Should not include unrequested fields'
  end

  # Test filter_records_response with invalid response
  def test_filter_records_response_invalid
    result = filter_records_response('not a hash', ['status'])

    assert_equal 'not a hash', result, 'Should return input unchanged for invalid response'
  end

  # Test estimate_tokens
  def test_estimate_tokens
    text = 'This is a test string with some words'
    tokens = estimate_tokens(text)

    # Should use 1.5 chars per token heuristic
    expected = (text.length / 1.5).round
    assert_equal expected, tokens
  end

  # Test estimate_tokens with empty string
  def test_estimate_tokens_empty
    tokens = estimate_tokens('')

    assert_equal 0, tokens
  end

  # Test estimate_tokens with JSON
  def test_estimate_tokens_json
    json = '{"key": "value", "array": [1, 2, 3]}'
    tokens = estimate_tokens(json)

    expected = (json.length / 1.5).round
    assert_equal expected, tokens
  end

  # Test generate_summary
  def test_generate_summary
    response = {
      'items' => [
        { 'id' => 'rec_1', 'status' => 'active', 'priority' => 1 },
        { 'id' => 'rec_2', 'status' => 'active', 'priority' => 2 },
        { 'id' => 'rec_3', 'status' => 'pending', 'priority' => 1 }
      ],
      'total_count' => 3
    }

    result = generate_summary(response)

    assert result.is_a?(Hash), 'Should return hash'
    assert_equal 3, result[:count]
    assert_equal 3, result[:total_count]
    assert result[:fields_analyzed].include?('status')
    assert result[:fields_analyzed].include?('priority')
    assert_includes result[:summary], 'Found 3 records'
  end

  # Test generate_summary with many unique values
  def test_generate_summary_many_values
    items = (1..20).map { |i| { 'id' => "rec_#{i}", 'unique_field' => "value_#{i}" } }
    response = {
      'items' => items,
      'total_count' => 20
    }

    result = generate_summary(response)

    # Should summarize fields with >10 unique values
    assert_includes result[:summary], 'unique values'
  end

  # Test generate_summary with invalid response
  def test_generate_summary_invalid
    result = generate_summary('not a hash')

    assert_equal 'not a hash', result, 'Should return input unchanged for invalid response'
  end

  # Test format_as_plain_text with records
  def test_format_as_plain_text_with_records
    records = [
      { 'id' => 'rec_1', 'title' => 'Task 1', 'status' => 'active' },
      { 'id' => 'rec_2', 'title' => 'Task 2', 'status' => 'pending' }
    ]

    result = format_as_plain_text(records, 2)

    assert_includes result, 'Showing 2 of 2 total'
    assert_includes result, 'Record 1:'
    assert_includes result, 'rec_1'
    assert_includes result, 'Task 1'
    assert_includes result, 'active'
    assert_includes result, 'Record 2:'
    assert_includes result, 'rec_2'
    assert_includes result, 'pending'
  end

  # Test format_as_plain_text with filtered count
  def test_format_as_plain_text_with_filtered_count
    records = [
      { 'id' => 'rec_1', 'title' => 'Task 1' }
    ]

    result = format_as_plain_text(records, 100, 50)

    assert_includes result, 'Showing 1 of 50 filtered'
    assert_includes result, '100 total'
  end

  # Test format_as_plain_text with empty records
  def test_format_as_plain_text_empty
    result = format_as_plain_text([], 0)

    assert_includes result, 'No records found'
    assert_includes result, '0 of 0 total'
  end

  # Test format_as_plain_text with empty records but total > 0
  def test_format_as_plain_text_empty_with_total
    result = format_as_plain_text([], 100, 50)

    assert_includes result, 'No records found in displayed page'
    assert_includes result, '50 matching filter'
    assert_includes result, '100 total'
  end

  # Test format_as_plain_text with array values
  def test_format_as_plain_text_with_arrays
    records = [
      { 'id' => 'rec_1', 'tags' => %w[urgent bug] }
    ]

    result = format_as_plain_text(records, 1)

    assert_includes result, 'tags: urgent, bug'
  end

  # Test format_as_plain_text with hash values
  def test_format_as_plain_text_with_hashes
    records = [
      { 'id' => 'rec_1', 'metadata' => { 'key' => 'value' } }
    ]

    result = format_as_plain_text(records, 1)

    assert_includes result, 'metadata: '
  end

  # Test filter_record_fields
  def test_filter_record_fields
    record = {
      'id' => 'rec_1',
      'title' => 'Task 1',
      'status' => 'active',
      'priority' => 1,
      'description' => 'Long description'
    }

    result = filter_record_fields(record, %w[id title status])

    assert_equal 3, result.keys.size
    assert_equal 'rec_1', result['id']
    assert_equal 'Task 1', result['title']
    assert_equal 'active', result['status']
    refute result.key?('priority'), 'Should not include unrequested fields'
    refute result.key?('description'), 'Should not include unrequested fields'
  end

  # Test filter_record_fields with invalid record
  def test_filter_record_fields_invalid
    result = filter_record_fields('not a hash', ['id'])

    assert_equal 'not a hash', result, 'Should return input unchanged for invalid record'
  end

  # Test filter_record_fields with missing fields
  def test_filter_record_fields_missing
    record = { 'id' => 'rec_1' }

    result = filter_record_fields(record, %w[id title status])

    assert_equal 1, result.keys.size
    assert_equal 'rec_1', result['id']
    refute result.key?('title'), 'Should not include missing fields'
    refute result.key?('status'), 'Should not include missing fields'
  end

  # Test truncate_value returns value as-is
  def test_truncate_value_no_truncation
    long_value = 'A' * 1000

    result = truncate_value(long_value)

    assert_equal long_value, result, 'Should return value unchanged (no truncation)'
  end

  # Test truncate_value with nil
  def test_truncate_value_nil
    result = truncate_value(nil)

    assert_nil result
  end

  # Test truncate_value with array
  def test_truncate_value_array
    array = [1, 2, 3, 4, 5]

    result = truncate_value(array)

    assert_equal array, result
  end

  # Test truncate_value with hash
  def test_truncate_value_hash
    hash = { 'key' => 'value' }

    result = truncate_value(hash)

    assert_equal hash, result
  end

  # Test filter_field_structure with empty choices
  def test_filter_field_structure_empty_choices
    field = {
      'slug' => 'status',
      'label' => 'Status',
      'field_type' => 'statusfield',
      'params' => {
        'choices' => []
      }
    }

    result = filter_field_structure(field)

    assert_equal [], result['params']['choices']
  end

  # Test filter_field_structure with only required param
  def test_filter_field_structure_only_required
    field = {
      'slug' => 'name',
      'label' => 'Name',
      'field_type' => 'textfield',
      'params' => {
        'required' => true,
        'display_format' => 'default' # Should be filtered
      }
    }

    result = filter_field_structure(field)

    assert_equal true, result['params']['required']
    assert_equal 1, result['params'].keys.size
  end

  # Test filter_field_structure with linked_application but no entries_allowed
  def test_filter_field_structure_linked_no_entries
    field = {
      'slug' => 'project',
      'label' => 'Project',
      'field_type' => 'linkedrecordfield',
      'params' => {
        'linked_application' => 'tbl_projects'
      }
    }

    result = filter_field_structure(field)

    assert_equal 'tbl_projects', result['params']['linked_application']
    refute result['params'].key?('entries_allowed')
  end

  # Test truncate_value with SmartDoc structure (Hash)
  def test_truncate_value_smartdoc_hash
    smartdoc = {
      'data' => {
        'type' => 'doc',
        'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Hello' }] }]
      },
      'html' => '<p>Hello</p>',
      'preview' => 'Hello'
    }

    result = truncate_value(smartdoc)

    assert_equal '<p>Hello</p>', result, 'Should extract HTML from SmartDoc structure'
  end

  # Test truncate_value with SmartDoc as JSON string (cache scenario)
  def test_truncate_value_smartdoc_json_string
    smartdoc = {
      'data' => {
        'type' => 'doc',
        'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Hello' }] }]
      },
      'html' => '<p>Hello from JSON</p>',
      'preview' => 'Hello from JSON'
    }
    json_string = smartdoc.to_json

    result = truncate_value(json_string)

    assert_equal '<p>Hello from JSON</p>', result, 'Should parse JSON string and extract HTML from SmartDoc'
  end

  # Test truncate_value with SmartDoc with empty HTML
  def test_truncate_value_smartdoc_empty_html
    smartdoc = {
      'data' => {
        'type' => 'doc',
        'content' => []
      },
      'html' => '',
      'preview' => ''
    }

    result = truncate_value(smartdoc)

    assert_equal '', result, 'Should return empty string for empty HTML'
  end

  # Test truncate_value with SmartDoc with nil HTML
  def test_truncate_value_smartdoc_nil_html
    smartdoc = {
      'data' => {
        'type' => 'doc',
        'content' => []
      },
      'html' => nil,
      'preview' => ''
    }

    result = truncate_value(smartdoc)

    assert_equal '', result, 'Should return empty string for nil HTML'
  end

  # Test truncate_value with non-SmartDoc hash (missing html key)
  def test_truncate_value_non_smartdoc_hash
    non_smartdoc = {
      'data' => { 'some' => 'data' },
      'preview' => 'Not a SmartDoc'
    }

    result = truncate_value(non_smartdoc)

    assert_equal non_smartdoc, result, 'Should return original value if not a SmartDoc (missing html key)'
  end

  # Test truncate_value with non-SmartDoc JSON string
  def test_truncate_value_non_smartdoc_json_string
    non_smartdoc = { 'name' => 'Test', 'value' => 123 }
    json_string = non_smartdoc.to_json

    result = truncate_value(json_string)

    assert_equal json_string, result, 'Should return original JSON string if not a SmartDoc'
  end

  # Test truncate_value with invalid JSON string
  def test_truncate_value_invalid_json
    invalid_json = 'This is not JSON {invalid'

    result = truncate_value(invalid_json)

    assert_equal invalid_json, result, 'Should return original string if JSON parsing fails'
  end

  # Test smartdoc_value? with valid SmartDoc
  def test_smartdoc_value_valid
    smartdoc = {
      'data' => { 'type' => 'doc' },
      'html' => '<p>Test</p>'
    }

    assert smartdoc_value?(smartdoc), 'Should detect valid SmartDoc structure'
  end

  # Test smartdoc_value? with symbol keys
  def test_smartdoc_value_symbol_keys
    smartdoc = {
      data: { type: 'doc' },
      html: '<p>Test</p>'
    }

    assert smartdoc_value?(smartdoc), 'Should detect SmartDoc with symbol keys'
  end

  # Test smartdoc_value? with missing html key
  def test_smartdoc_value_missing_html
    not_smartdoc = {
      'data' => { 'type' => 'doc' },
      'preview' => 'Test'
    }

    refute smartdoc_value?(not_smartdoc), 'Should not detect as SmartDoc without html key'
  end

  # Test smartdoc_value? with missing data key
  def test_smartdoc_value_missing_data
    not_smartdoc = {
      'html' => '<p>Test</p>',
      'preview' => 'Test'
    }

    refute smartdoc_value?(not_smartdoc), 'Should not detect as SmartDoc without data key'
  end

  # Test smartdoc_value? with non-hash value
  def test_smartdoc_value_non_hash
    refute smartdoc_value?('string'), 'Should not detect string as SmartDoc'
    refute smartdoc_value?(123), 'Should not detect number as SmartDoc'
    refute smartdoc_value?(nil), 'Should not detect nil as SmartDoc'
  end

  # Test large content warning for textarea fields
  def test_filter_field_structure_large_content_warning
    field = {
      'slug' => 'notes',
      'label' => 'Notes',
      'field_type' => 'textarea'
    }

    result = filter_field_structure(field)

    assert result.key?('large_content_warning'), 'Should have large content warning for textarea'
    assert_includes result['large_content_warning'], 'extensive data'
  end

  # Test large content warning for richtextarea fields
  def test_filter_field_structure_large_content_warning_richtext
    field = {
      'slug' => 'description',
      'label' => 'Description',
      'field_type' => 'richtextarea'
    }

    result = filter_field_structure(field)

    assert result.key?('large_content_warning'), 'Should have large content warning for richtextarea'
  end

  # Test no large content warning for regular text field
  def test_filter_field_structure_no_large_content_warning
    field = {
      'slug' => 'title',
      'label' => 'Title',
      'field_type' => 'textfield'
    }

    result = filter_field_structure(field)

    refute result.key?('large_content_warning'), 'Should not have large content warning for textfield'
  end
end
