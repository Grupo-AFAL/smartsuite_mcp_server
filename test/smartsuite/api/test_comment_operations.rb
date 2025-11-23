# frozen_string_literal: true

require_relative '../../test_helper'
require 'net/http'
require_relative '../../../lib/smartsuite_client'

class TestCommentOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @client = SmartSuiteClient.new(@api_key, @account_id)
  end

  def test_list_comments_success
    record_id = 'rec123'
    comments = [
      {
        'id' => 'comment1',
        'message' => {
          'data' => {
            'type' => 'doc',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [{ 'type' => 'text', 'text' => 'First comment' }]
              }
            ]
          }
        },
        'created_by' => 'user1',
        'created_on' => '2025-01-01T10:00:00Z'
      },
      {
        'id' => 'comment2',
        'message' => {
          'data' => {
            'type' => 'doc',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [{ 'type' => 'text', 'text' => 'Second comment' }]
              }
            ]
          }
        },
        'created_by' => 'user2',
        'created_on' => '2025-01-02T10:00:00Z'
      }
    ]
    # API returns hash with 'results' key
    expected_response = { 'results' => comments, 'count' => nil }

    # Mock api_request method
    @client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      expected_response
    end

    result = @client.list_comments(record_id, format: :json)

    assert_equal 2, result['count']
    assert_equal 'comment1', result['results'][0]['id']
    assert_equal 'comment2', result['results'][1]['id']
    assert_equal 'First comment', result['results'][0]['message']['data']['content'][0]['content'][0]['text']
  end

  def test_list_comments_missing_record_id
    assert_raises(ArgumentError, 'record_id is required') do
      @client.list_comments(nil)
    end

    assert_raises(ArgumentError, 'record_id is required') do
      @client.list_comments('')
    end
  end

  def test_add_comment_success
    table_id = 'app123'
    record_id = 'rec456'
    message = 'This is a test comment'

    expected_response = {
      'id' => 'comment_new',
      'message' => {
        'data' => {
          'type' => 'doc',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => message }]
            }
          ]
        }
      },
      'application' => table_id,
      'record' => record_id,
      'assigned_to' => nil,
      'created_on' => '2025-01-05T12:00:00Z'
    }

    # Mock api_request method
    @client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      expected_response
    end

    result = @client.add_comment(table_id, record_id, message, nil, format: :json)

    assert_equal 'comment_new', result['id']
    assert_equal table_id, result['application']
    assert_equal record_id, result['record']
    assert_nil result['assigned_to']
  end

  def test_add_comment_with_assignment
    table_id = 'app123'
    record_id = 'rec456'
    message = 'Review this please'
    assigned_to = 'user789'

    expected_response = {
      'id' => 'comment_assigned',
      'message' => {
        'data' => {
          'type' => 'doc',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [{ 'type' => 'text', 'text' => message }]
            }
          ]
        }
      },
      'application' => table_id,
      'record' => record_id,
      'assigned_to' => assigned_to,
      'created_on' => '2025-01-05T12:00:00Z'
    }

    # Mock api_request method
    @client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      expected_response
    end

    result = @client.add_comment(table_id, record_id, message, assigned_to, format: :json)

    assert_equal 'comment_assigned', result['id']
    assert_equal assigned_to, result['assigned_to']
  end

  def test_add_comment_missing_table_id
    assert_raises(ArgumentError, 'table_id is required') do
      @client.add_comment(nil, 'rec123', 'message')
    end

    assert_raises(ArgumentError, 'table_id is required') do
      @client.add_comment('', 'rec123', 'message')
    end
  end

  def test_add_comment_missing_record_id
    assert_raises(ArgumentError, 'record_id is required') do
      @client.add_comment('app123', nil, 'message')
    end

    assert_raises(ArgumentError, 'record_id is required') do
      @client.add_comment('app123', '', 'message')
    end
  end

  def test_add_comment_missing_message
    assert_raises(ArgumentError, 'message is required') do
      @client.add_comment('app123', 'rec456', nil)
    end

    assert_raises(ArgumentError, 'message is required') do
      @client.add_comment('app123', 'rec456', '')
    end
  end

  def test_format_message_structure
    # Test that the message formatting creates the correct rich text structure
    message_text = 'Hello world'

    # We need to access the private method for testing
    formatted = @client.send(:format_message, message_text)

    assert_equal 'doc', formatted['data']['type']
    assert_equal 1, formatted['data']['content'].length
    assert_equal 'paragraph', formatted['data']['content'][0]['type']
    assert_equal 1, formatted['data']['content'][0]['content'].length
    assert_equal 'text', formatted['data']['content'][0]['content'][0]['type']
    assert_equal message_text, formatted['data']['content'][0]['content'][0]['text']
  end

  def test_list_comments_api_endpoint
    record_id = 'rec123'

    # Track endpoint and method
    endpoint_called = nil
    method_called = nil

    @client.define_singleton_method(:api_request) do |method, endpoint, _body = nil|
      endpoint_called = endpoint
      method_called = method
      { 'results' => [], 'count' => nil }
    end

    @client.list_comments(record_id)

    assert_equal "/comments/?record=#{record_id}", endpoint_called
    assert_equal :get, method_called
  end

  def test_add_comment_api_endpoint
    table_id = 'app123'
    record_id = 'rec456'
    message = 'Test'

    # Track endpoint, method, and body
    endpoint_called = nil
    method_called = nil
    body_sent = nil

    @client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      endpoint_called = endpoint
      method_called = method
      body_sent = body
      { 'id' => 'new_comment' }
    end

    @client.add_comment(table_id, record_id, message)

    assert_equal '/comments/', endpoint_called
    assert_equal :post, method_called
    assert_equal table_id, body_sent['application']
    assert_equal record_id, body_sent['record']
    assert_equal 'Test', body_sent['message']['data']['content'][0]['content'][0]['text']
  end
end
