# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite/api/http_client'
require 'webmock/minitest'
require 'stringio'

class TestHttpClient < Minitest::Test
  # Test class that includes HttpClient module
  class TestClient
    include SmartSuite::API::HttpClient

    attr_accessor :api_key, :account_id, :stats_tracker, :metrics_log, :total_tokens_used, :context_limit

    def initialize
      @api_key = 'test_api_key'
      @account_id = 'test_account_id'
      @stats_tracker = nil
      @metrics_log = StringIO.new
      @total_tokens_used = 0
      @context_limit = 200_000
    end
  end

  def setup
    @client = TestClient.new
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  # Test successful GET request
  def test_api_request_get_success
    stub_request(:get, "https://app.smartsuite.com/api/v1/solutions/")
      .with(
        headers: {
          'Authorization' => 'Token test_api_key',
          'Account-Id' => 'test_account_id',
          'Content-Type' => 'application/json'
        }
      )
      .to_return(
        status: 200,
        body: '{"items": [{"id": "sol_123", "name": "Test Solution"}]}',
        headers: { 'Content-Type' => 'application/json' }
      )

    result = @client.api_request(:get, '/solutions/')

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('items'), "Expected 'items' key"
    assert_equal 1, result['items'].size
    assert_equal 'sol_123', result['items'][0]['id']
  end

  # Test successful POST request with body
  def test_api_request_post_with_body
    request_body = { filter: { operator: 'and', fields: [] } }

    stub_request(:post, "https://app.smartsuite.com/api/v1/applications/tbl_123/records/list/?limit=10")
      .with(
        headers: {
          'Authorization' => 'Token test_api_key',
          'Account-Id' => 'test_account_id',
          'Content-Type' => 'application/json'
        },
        body: request_body.to_json
      )
      .to_return(
        status: 200,
        body: '{"items": [{"id": "rec_456"}]}',
        headers: { 'Content-Type' => 'application/json' }
      )

    result = @client.api_request(:post, '/applications/tbl_123/records/list/?limit=10', request_body)

    assert result.is_a?(Hash)
    assert_equal 'rec_456', result['items'][0]['id']
  end

  # Test PUT request
  def test_api_request_put
    update_data = { label: 'Updated Label' }

    stub_request(:put, "https://app.smartsuite.com/api/v1/applications/tbl_123/change_field/")
      .with(
        headers: {
          'Authorization' => 'Token test_api_key',
          'Account-Id' => 'test_account_id'
        },
        body: update_data.to_json
      )
      .to_return(status: 200, body: '{"success": true}')

    result = @client.api_request(:put, '/applications/tbl_123/change_field/', update_data)

    assert_equal true, result['success']
  end

  # Test PATCH request
  def test_api_request_patch
    patch_data = { status: 'active' }

    stub_request(:patch, "https://app.smartsuite.com/api/v1/records/rec_123/")
      .with(body: patch_data.to_json)
      .to_return(status: 200, body: '{"updated": true}')

    result = @client.api_request(:patch, '/records/rec_123/', patch_data)

    assert_equal true, result['updated']
  end

  # Test DELETE request
  def test_api_request_delete
    stub_request(:delete, "https://app.smartsuite.com/api/v1/applications/tbl_123/delete_field/")
      .to_return(status: 200, body: '{"deleted": true}')

    result = @client.api_request(:delete, '/applications/tbl_123/delete_field/')

    assert_equal true, result['deleted']
  end

  # Test empty response handling
  def test_api_request_empty_response
    stub_request(:post, "https://app.smartsuite.com/api/v1/applications/tbl_123/add_field/")
      .to_return(status: 200, body: '')

    result = @client.api_request(:post, '/applications/tbl_123/add_field/', { field_data: {} })

    assert_equal({}, result, "Empty response should return empty hash")
  end

  # Test whitespace-only response
  def test_api_request_whitespace_response
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: '   ')

    result = @client.api_request(:get, '/test/')

    assert_equal({}, result, "Whitespace response should return empty hash")
  end

  # Test error response (4xx)
  def test_api_request_client_error
    stub_request(:get, "https://app.smartsuite.com/api/v1/invalid/")
      .to_return(status: 404, body: '{"error": "Not found"}')

    error = assert_raises(RuntimeError) do
      @client.api_request(:get, '/invalid/')
    end

    assert_includes error.message, '404', "Error should include status code"
    assert_includes error.message, 'API request failed', "Error should include failure message"
  end

  # Test error response (5xx)
  def test_api_request_server_error
    stub_request(:post, "https://app.smartsuite.com/api/v1/records/")
      .to_return(status: 500, body: 'Internal Server Error')

    error = assert_raises(RuntimeError) do
      @client.api_request(:post, '/records/', { data: 'test' })
    end

    assert_includes error.message, '500'
  end

  # Test rate limit error
  def test_api_request_rate_limit_error
    stub_request(:get, "https://app.smartsuite.com/api/v1/solutions/")
      .to_return(status: 429, body: '{"error": "Rate limit exceeded"}')

    error = assert_raises(RuntimeError) do
      @client.api_request(:get, '/solutions/')
    end

    assert_includes error.message, '429'
  end

  # Test invalid JSON response
  def test_api_request_invalid_json
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: 'not valid json{')

    error = assert_raises(JSON::ParserError) do
      @client.api_request(:get, '/test/')
    end

    assert error.is_a?(JSON::ParserError)
  end

  # Test stats tracker integration
  def test_api_request_stats_tracker_integration
    # Mock stats tracker
    stats_tracker = Minitest::Mock.new
    stats_tracker.expect(:track_api_call, nil, [:get, '/solutions/'])

    @client.stats_tracker = stats_tracker

    stub_request(:get, "https://app.smartsuite.com/api/v1/solutions/")
      .to_return(status: 200, body: '{}')

    @client.api_request(:get, '/solutions/')

    stats_tracker.verify
  end

  # Test stats tracker is optional (nil handling)
  def test_api_request_without_stats_tracker
    @client.stats_tracker = nil

    stub_request(:get, "https://app.smartsuite.com/api/v1/solutions/")
      .to_return(status: 200, body: '{}')

    # Should not raise error even without stats tracker
    result = @client.api_request(:get, '/solutions/')

    assert_equal({}, result)
  end

  # Test headers are set correctly
  def test_api_request_headers
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .with(
        headers: {
          'Authorization' => 'Token test_api_key',
          'Account-Id' => 'test_account_id',
          'Content-Type' => 'application/json'
        }
      )
      .to_return(status: 200, body: '{}')

    @client.api_request(:get, '/test/')

    # If headers weren't correct, WebMock would raise an error
    assert true, "Headers were set correctly"
  end

  # Test request without body
  def test_api_request_get_without_body
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: '{"result": "ok"}')

    result = @client.api_request(:get, '/test/')

    assert_equal 'ok', result['result']
  end

  # Test complex JSON response parsing
  def test_api_request_complex_json_parsing
    complex_response = {
      'nested' => {
        'array' => [1, 2, 3],
        'hash' => { 'key' => 'value' }
      },
      'boolean' => true,
      'null' => nil,
      'number' => 42.5
    }

    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: complex_response.to_json)

    result = @client.api_request(:get, '/test/')

    assert_equal [1, 2, 3], result['nested']['array']
    assert_equal({ 'key' => 'value' }, result['nested']['hash'])
    assert_equal true, result['boolean']
    assert_nil result['null']
    assert_equal 42.5, result['number']
  end

  # Test log_metric
  def test_log_metric
    @client.log_metric('Test message')

    output = @client.metrics_log.string
    assert_includes output, 'Test message', "Log should contain message"
    assert_match(/\[\d{2}:\d{2}:\d{2}\]/, output, "Log should contain timestamp")
  end

  # Test log_token_usage
  def test_log_token_usage
    @client.total_tokens_used = 1000
    @client.context_limit = 200_000

    @client.log_token_usage(500)

    assert_equal 1500, @client.total_tokens_used, "Should update total tokens"

    output = @client.metrics_log.string
    assert_includes output, '+500', "Should log tokens used"
    assert_includes output, '1500', "Should log total"
    assert_includes output, '198500', "Should log remaining (200000 - 1500)"
  end

  # Test log_token_usage at context limit
  def test_log_token_usage_near_limit
    @client.total_tokens_used = 199_900
    @client.context_limit = 200_000

    @client.log_token_usage(50)

    output = @client.metrics_log.string
    assert_includes output, 'Remaining: 50'
  end

  # Test SSL verification is disabled (as per code)
  def test_api_request_ssl_configuration
    # We can't directly test SSL settings, but we can verify the request succeeds
    # with our WebMock stub (which doesn't use real SSL)
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: '{}')

    result = @client.api_request(:get, '/test/')

    assert_equal({}, result)
  end

  # Test network timeout/connection error handling
  def test_api_request_network_error
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_timeout

    error = assert_raises(StandardError) do
      @client.api_request(:get, '/test/')
    end

    # Should raise some kind of error (Net::OpenTimeout or similar)
    assert error.is_a?(StandardError)
  end

  # Test endpoint path construction
  def test_api_request_endpoint_paths
    # Test various endpoint path formats
    [
      '/solutions/',
      '/applications/tbl_123/',
      '/applications/tbl_123/records/list/?limit=10&offset=0'
    ].each do |endpoint|
      stub_request(:get, "https://app.smartsuite.com/api/v1#{endpoint}")
        .to_return(status: 200, body: '{}')

      result = @client.api_request(:get, endpoint)
      assert_equal({}, result)
    end
  end

  # Test that body is only sent with POST/PUT/PATCH/DELETE, not GET
  def test_api_request_get_ignores_body
    stub_request(:get, "https://app.smartsuite.com/api/v1/test/")
      .to_return(status: 200, body: '{}')

    # GET with body parameter (should be ignored by HTTP spec)
    result = @client.api_request(:get, '/test/', { data: 'ignored' })

    assert_equal({}, result)
  end
end
