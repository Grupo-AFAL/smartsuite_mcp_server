require 'minitest/autorun'
require 'json'
require 'stringio'
require_relative '../smartsuite_server'

class SmartSuiteServerTest < Minitest::Test
  def setup
    # Set up test environment variables
    ENV['SMARTSUITE_API_KEY'] = 'test_api_key_12345'
    ENV['SMARTSUITE_ACCOUNT_ID'] = 'test_account_id'

    # Create a new server instance
    @server = SmartSuiteServer.new
  end

  def teardown
    # Clean up any test stats file
    stats_file = File.join(Dir.home, '.smartsuite_mcp_stats.json')
    File.delete(stats_file) if File.exist?(stats_file)
  end

  # Helper method to call private methods for testing
  def call_private_method(method_name, *args)
    @server.send(method_name, *args)
  end

  # Test initialization
  def test_server_initialization
    assert_instance_of SmartSuiteServer, @server
  end

  def test_server_requires_api_key
    ENV.delete('SMARTSUITE_API_KEY')
    error = assert_raises(RuntimeError) do
      SmartSuiteServer.new
    end
    assert_match(/SMARTSUITE_API_KEY/, error.message)
    # Restore for other tests
    ENV['SMARTSUITE_API_KEY'] = 'test_api_key_12345'
  end

  def test_server_requires_account_id
    ENV.delete('SMARTSUITE_ACCOUNT_ID')
    error = assert_raises(RuntimeError) do
      SmartSuiteServer.new
    end
    assert_match(/SMARTSUITE_ACCOUNT_ID/, error.message)
    # Restore for other tests
    ENV['SMARTSUITE_ACCOUNT_ID'] = 'test_account_id'
  end

  # Test MCP protocol methods
  def test_handle_initialize
    request = {
      'id' => 1,
      'method' => 'initialize',
      'params' => {}
    }

    response = call_private_method(:handle_initialize, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 1, response['id']
    assert_equal '2024-11-05', response['result']['protocolVersion']
    assert_equal 'smartsuite-server', response['result']['serverInfo']['name']
    assert_equal '1.0.1', response['result']['serverInfo']['version']
    assert response['result']['capabilities']['tools']
    assert response['result']['capabilities']['prompts']
    assert response['result']['capabilities']['resources']
  end

  def test_handle_tools_list
    request = {
      'id' => 1,
      'method' => 'tools/list',
      'params' => {}
    }

    response = call_private_method(:handle_tools_list, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 1, response['id']
    assert_instance_of Array, response['result']['tools']

    tool_names = response['result']['tools'].map { |t| t['name'] }
    assert_includes tool_names, 'list_solutions'
    assert_includes tool_names, 'list_tables'
    assert_includes tool_names, 'list_records'
    assert_includes tool_names, 'get_record'
    assert_includes tool_names, 'create_record'
    assert_includes tool_names, 'update_record'
    assert_includes tool_names, 'get_api_stats'
    assert_includes tool_names, 'reset_api_stats'
  end

  def test_handle_prompts_list
    request = {
      'id' => 2,
      'method' => 'prompts/list',
      'params' => {}
    }

    response = call_private_method(:handle_prompts_list, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 2, response['id']
    assert_equal [], response['result']['prompts']
  end

  def test_handle_resources_list
    request = {
      'id' => 3,
      'method' => 'resources/list',
      'params' => {}
    }

    response = call_private_method(:handle_resources_list, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 3, response['id']
    assert_equal [], response['result']['resources']
  end

  def test_handle_unknown_method
    request = {
      'id' => 4,
      'method' => 'unknown/method',
      'params' => {}
    }

    response = call_private_method(:handle_request, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 4, response['id']
    assert_equal(-32601, response['error']['code'])
    assert_match(/Method not found/, response['error']['message'])
  end

  # Test API statistics tracking
  def test_initialize_stats
    stats = call_private_method(:initialize_stats)

    assert_equal 0, stats['total_calls']
    assert_equal({}, stats['by_user'])
    assert_equal({}, stats['by_solution'])
    assert_equal({}, stats['by_table'])
    assert_equal({}, stats['by_method'])
    assert_equal({}, stats['by_endpoint'])
    assert_nil stats['first_call']
    assert_nil stats['last_call']
  end

  def test_extract_ids_from_endpoint
    # Test extracting solution ID
    call_private_method(:extract_ids_from_endpoint, '/solutions/sol_abc123/')
    stats = call_private_method(:get_api_stats)
    assert_equal 1, stats['by_solution']['sol_abc123']

    # Test extracting table ID
    call_private_method(:extract_ids_from_endpoint, '/applications/tbl_123/records/')
    stats = call_private_method(:get_api_stats)
    assert_equal 1, stats['by_table']['tbl_123']
  end

  def test_reset_api_stats
    # Track some calls first
    call_private_method(:track_api_call, :get, '/solutions/')
    call_private_method(:track_api_call, :post, '/applications/abc/records/')

    # Verify stats exist
    stats = call_private_method(:get_api_stats)
    assert stats['summary']['total_calls'] > 0

    # Reset stats
    result = call_private_method(:reset_api_stats)

    assert_equal 'success', result['status']

    # Verify stats are reset
    stats = call_private_method(:get_api_stats)
    assert_equal 0, stats['summary']['total_calls']
  end

  # Test data formatting for list methods
  def test_list_solutions_formats_hash_response
    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'logo_icon' => 'star',
          'logo_color' => '#FF0000',
          'extra_field' => 'should be filtered'
        },
        {
          'id' => 'sol_2',
          'name' => 'Solution 2',
          'logo_icon' => 'heart',
          'logo_color' => '#00FF00'
        }
      ]
    }

    # Mock the api_request method (accepts 3 args: method, endpoint, body)
    @server.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = call_private_method(:list_solutions)

    assert_equal 2, result['count']
    assert_equal 2, result['solutions'].length
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'Solution 1', result['solutions'][0]['name']
    refute result['solutions'][0].key?('extra_field'), 'Should filter out extra fields'
  end

  def test_list_solutions_formats_array_response
    mock_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution 1',
        'logo_icon' => 'star',
        'logo_color' => '#FF0000'
      }
    ]

    # Mock the api_request method
    @server.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = call_private_method(:list_solutions)

    assert_equal 1, result['count']
    assert_equal 1, result['solutions'].length
  end

  def test_list_tables_formats_response
    mock_response = {
      'items' => [
        {
          'id' => 'tbl_1',
          'name' => 'Table 1',
          'solution_id' => 'sol_1',
          'structure' => 'should be filtered'
        }
      ]
    }

    # Mock the api_request method
    @server.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = call_private_method(:list_tables)

    assert_equal 1, result['count']
    assert_equal 'tbl_1', result['tables'][0]['id']
    assert_equal 'Table 1', result['tables'][0]['name']
    assert_equal 'sol_1', result['tables'][0]['solution_id']
    refute result['tables'][0].key?('structure'), 'Should filter out structure field'
  end

  # Test tool call handling
  def test_handle_tool_call_get_api_stats
    request = {
      'id' => 5,
      'method' => 'tools/call',
      'params' => {
        'name' => 'get_api_stats',
        'arguments' => {}
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 5, response['id']
    assert response['result']['content']
    assert_equal 'text', response['result']['content'][0]['type']

    # Parse the JSON response
    stats = JSON.parse(response['result']['content'][0]['text'])
    assert stats['summary']
    assert_kind_of Integer, stats['summary']['total_calls']
  end

  def test_handle_tool_call_reset_api_stats
    request = {
      'id' => 6,
      'method' => 'tools/call',
      'params' => {
        'name' => 'reset_api_stats',
        'arguments' => {}
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 6, response['id']

    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'success', result['status']
  end

  def test_handle_tool_call_unknown_tool
    request = {
      'id' => 7,
      'method' => 'tools/call',
      'params' => {
        'name' => 'unknown_tool',
        'arguments' => {}
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 7, response['id']
    assert_equal(-32602, response['error']['code'])
    assert_match(/Unknown tool/, response['error']['message'])
  end

  # Test error handling through handle_request
  def test_error_response_format
    # Test that error responses have correct format
    request = {
      'id' => 10,
      'method' => 'invalid/method',
      'params' => {}
    }

    response = call_private_method(:handle_request, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 10, response['id']
    assert response['error']
    assert response['error']['code']
    assert response['error']['message']
  end
end
