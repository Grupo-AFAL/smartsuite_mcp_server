require 'minitest/autorun'
require 'json'
require 'stringio'
require_relative '../smartsuite_server'
require_relative '../lib/smartsuite_client'
require_relative '../lib/api_stats_tracker'

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
    assert_includes tool_names, 'list_members'
    assert_includes tool_names, 'list_tables'
    assert_includes tool_names, 'list_records'
    assert_includes tool_names, 'get_record'
    assert_includes tool_names, 'create_record'
    assert_includes tool_names, 'update_record'
    assert_includes tool_names, 'delete_record'
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

    # Should now return prompts for common filtering patterns
    prompts = response['result']['prompts']
    assert prompts.length > 0, 'Should return at least one prompt'

    # Check that filter_active_records prompt exists
    active_prompt = prompts.find { |p| p['name'] == 'filter_active_records' }
    refute_nil active_prompt, 'Should include filter_active_records prompt'
    assert_equal 'Example: Filter records where status is "active"', active_prompt['description']
  end

  def test_handle_prompt_get
    request = {
      'id' => 10,
      'method' => 'prompts/get',
      'params' => {
        'name' => 'filter_active_records',
        'arguments' => {
          'table_id' => 'tbl_123',
          'fields' => 'status,priority'
        }
      }
    }

    response = call_private_method(:handle_prompt_get, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 10, response['id']

    # Check that the prompt text includes the filter structure
    messages = response['result']['messages']
    assert_equal 1, messages.length
    assert_equal 'user', messages[0]['role']

    prompt_text = messages[0]['content']['text']
    assert_includes prompt_text, 'list_records', 'Should mention list_records tool'
    assert_includes prompt_text, 'tbl_123', 'Should include table_id'
    assert_includes prompt_text, '"operator": "and"', 'Should include filter operator'
    assert_includes prompt_text, '"comparison": "is"', 'Should include comparison operator'
    assert_includes prompt_text, '"value": "active"', 'Should include active value'
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
  def test_stats_tracker_initialization
    tracker = ApiStatsTracker.new('test_key')
    stats = tracker.get_stats

    assert_equal 0, stats['summary']['total_calls']
    assert_equal 0, stats['summary']['unique_users']
    assert_equal 0, stats['summary']['unique_solutions']
    assert_equal 0, stats['summary']['unique_tables']
  end

  def test_stats_tracker_tracks_calls
    tracker = ApiStatsTracker.new('test_key')

    # Track some calls
    tracker.track_api_call(:get, '/solutions/sol_abc123/')
    tracker.track_api_call(:post, '/applications/tbl_123/records/')

    stats = tracker.get_stats

    assert_equal 2, stats['summary']['total_calls']
    assert_equal 1, stats['by_solution']['sol_abc123']
    assert_equal 1, stats['by_table']['tbl_123']
    assert_equal 1, stats['by_method']['GET']
    assert_equal 1, stats['by_method']['POST']
  end

  def test_stats_tracker_reset
    tracker = ApiStatsTracker.new('test_key')

    # Track some calls
    tracker.track_api_call(:get, '/solutions/')

    # Verify stats exist
    assert tracker.get_stats['summary']['total_calls'] > 0

    # Reset stats
    result = tracker.reset_stats
    assert_equal 'success', result['status']

    # Verify stats are reset
    assert_equal 0, tracker.get_stats['summary']['total_calls']
  end

  # Test SmartSuiteClient data formatting
  def test_client_list_solutions_formats_hash_response
    client = SmartSuiteClient.new('test_key', 'test_account')

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

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions

    assert_equal 2, result['count']
    assert_equal 2, result['solutions'].length
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'Solution 1', result['solutions'][0]['name']
    refute result['solutions'][0].key?('extra_field'), 'Should filter out extra fields'
  end

  def test_client_list_solutions_formats_array_response
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution 1',
        'logo_icon' => 'star',
        'logo_color' => '#FF0000'
      }
    ]

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions

    assert_equal 1, result['count']
    assert_equal 1, result['solutions'].length
  end

  def test_client_list_tables_formats_response
    client = SmartSuiteClient.new('test_key', 'test_account')

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
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_tables

    assert_equal 1, result['count']
    assert_equal 'tbl_1', result['tables'][0]['id']
    assert_equal 'Table 1', result['tables'][0]['name']
    assert_equal 'sol_1', result['tables'][0]['solution_id']
    refute result['tables'][0].key?('structure'), 'Should filter out structure field'
  end

  def test_client_list_tables_filters_by_solution_id
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track the endpoint that was called
    called_endpoint = nil

    # Mock response - API returns only filtered tables
    mock_response = {
      'items' => [
        {
          'id' => 'tbl_1',
          'name' => 'Customers',
          'solution_id' => 'sol_1'
        },
        {
          'id' => 'tbl_2',
          'name' => 'Orders',
          'solution_id' => 'sol_1'
        }
      ]
    }

    # Mock the api_request method to track endpoint
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test filtering by solution_id
    result = client.list_tables(solution_id: 'sol_1')

    # Verify the API was called with the solution query parameter
    assert_equal '/applications/?solution=sol_1', called_endpoint, 'Should use solution query parameter'

    # Verify response
    assert_equal 2, result['count'], 'Should return only tables from sol_1'
    assert_equal 'tbl_1', result['tables'][0]['id']
    assert_equal 'tbl_2', result['tables'][1]['id']
  end

  def test_client_get_solution
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'id' => 'sol_123',
      'name' => 'Test Solution',
      'permissions' => {
        'members' => [
          {'access' => 'full_access', 'entity' => 'usr_1'},
          {'access' => 'assignee', 'entity' => 'usr_2'}
        ],
        'owners' => ['usr_3']
      }
    }

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.get_solution('sol_123')

    assert_equal 'sol_123', result['id']
    assert_equal 'Test Solution', result['name']
    assert result['permissions']
    assert result['permissions']['members']
  end

  def test_client_list_members
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'usr_123',
          'title' => 'John Doe',
          'email' => 'john@example.com',
          'first_name' => 'John',
          'last_name' => 'Doe',
          'role' => 'admin',
          'status' => 'active',
          'extra_field' => 'should be filtered'
        },
        {
          'id' => 'usr_456',
          'title' => 'Jane Smith',
          'email' => 'jane@example.com',
          'first_name' => 'Jane',
          'last_name' => 'Smith',
          'role' => 'member',
          'status' => 'active'
        }
      ],
      'total_count' => 2
    }

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_members

    assert_equal 2, result['count']
    assert_equal 2, result['total_count']
    assert_equal 2, result['members'].length
    assert_equal 'usr_123', result['members'][0]['id']
    assert_equal 'John Doe', result['members'][0]['title']
    assert_equal 'john@example.com', result['members'][0]['email']
    refute result['members'][0].key?('extra_field'), 'Should filter out extra fields'
  end

  def test_client_list_members_filtered_by_solution
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Mock solution response with permissions structure (includes team)
    mock_solution = {
      'id' => 'sol_123',
      'name' => 'Test Solution',
      'permissions' => {
        'members' => [
          {'access' => 'full_access', 'entity' => 'usr_123'}
        ],
        'owners' => ['usr_789'],
        'teams' => [
          {'access' => 'full_access', 'entity' => 'team_001'}
        ]
      }
    }

    # Mock team response
    mock_team = {
      'id' => 'team_001',
      'name' => 'Test Team',
      'members' => ['usr_456', 'usr_999']
    }

    # Mock members response (has 5 members total)
    mock_members = {
      'items' => [
        {
          'id' => 'usr_123',
          'title' => 'John Doe',
          'email' => 'john@example.com'
        },
        {
          'id' => 'usr_456',
          'title' => 'Jane Smith',
          'email' => 'jane@example.com'
        },
        {
          'id' => 'usr_789',
          'title' => 'Bob Wilson',
          'email' => 'bob@example.com'
        },
        {
          'id' => 'usr_999',
          'title' => 'Alice Brown',
          'email' => 'alice@example.com'
        },
        {
          'id' => 'usr_000',
          'title' => 'Not in Solution',
          'email' => 'not@example.com'
        }
      ],
      'total_count' => 5
    }

    # Mock teams list response
    mock_teams_list = [mock_team]

    # Mock the api_request method to return different data based on endpoint
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      if endpoint.include?('/solutions/')
        mock_solution
      elsif endpoint.include?('/teams/list/')
        mock_teams_list
      else
        mock_members
      end
    end

    result = client.list_members(100, 0, solution_id: 'sol_123')

    # Should return 4 members: usr_123 (direct member), usr_789 (owner), usr_456 and usr_999 (from team)
    assert_equal 4, result['count']
    assert_equal 4, result['members'].length
    assert_equal 'sol_123', result['filtered_by_solution']

    # Check that only solution members are returned (including team members)
    member_ids = result['members'].map { |m| m['id'] }
    assert_includes member_ids, 'usr_123', 'Should include direct member'
    assert_includes member_ids, 'usr_789', 'Should include owner'
    assert_includes member_ids, 'usr_456', 'Should include team member'
    assert_includes member_ids, 'usr_999', 'Should include team member'
    refute_includes member_ids, 'usr_000', 'Should not include member not in solution'
  end

  def test_client_get_table
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'id' => 'tbl_123',
      'name' => 'Customers',
      'solution_id' => 'sol_1',
      'structure' => [
        {
          'slug' => 'status',
          'label' => 'Status',
          'field_type' => 'statusfield'
        },
        {
          'slug' => 'priority',
          'label' => 'Priority',
          'field_type' => 'numberfield'
        }
      ]
    }

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.get_table('tbl_123')

    assert_equal 'tbl_123', result['id']
    assert_equal 'Customers', result['name']
    assert_equal 'sol_1', result['solution_id']
    refute_nil result['structure'], 'Should include structure'
    assert_equal 2, result['structure'].length, 'Should have 2 fields'
    assert_equal 'status', result['structure'][0]['slug']
    assert_equal 'priority', result['structure'][1]['slug']
  end

  # Test filtering and sorting
  def test_client_list_records_with_filter
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what body was sent
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_body = body
      {'items' => []}
    end

    filter = {
      'operator' => 'and',
      'fields' => [
        {'field' => 'status', 'comparison' => 'is', 'value' => 'active'}
      ]
    }
    client.list_records('tbl_123', 10, 0, filter: filter, fields: ['status'])

    assert_equal filter, sent_body[:filter]
    assert_equal 10, sent_body[:limit]
    assert_equal 0, sent_body[:offset]
  end

  def test_client_list_records_with_sort
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what body was sent
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    sort = [{'field' => 'created_on', 'direction' => 'desc'}]
    client.list_records('tbl_123', 10, 0, sort: sort, fields: ['status'])

    assert_equal sort, sent_body[:sort]
    # Without filter, limit is automatically reduced to 2
    assert_equal 2, sent_body[:limit], 'Should limit to 2 records without filter'
  end

  def test_client_list_records_with_filter_and_sort
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what body was sent
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    filter = {
      'operator' => 'and',
      'fields' => [
        {'field' => 'status', 'comparison' => 'is', 'value' => 'active'},
        {'field' => 'priority', 'comparison' => 'is_greater_than', 'value' => 3}
      ]
    }
    sort = [{'field' => 'created_on', 'direction' => 'desc'}, {'field' => 'title', 'direction' => 'asc'}]
    client.list_records('tbl_123', 20, 10, filter: filter, sort: sort, fields: ['status', 'priority'])

    assert_equal filter, sent_body[:filter]
    assert_equal sort, sent_body[:sort]
    assert_equal 20, sent_body[:limit]
    assert_equal 10, sent_body[:offset]
  end

  def test_client_list_records_without_filter_or_sort
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what body was sent
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    client.list_records('tbl_123', 50, 0, fields: ['status'])

    refute sent_body.key?(:filter), 'Should not include filter when nil'
    refute sent_body.key?(:sort), 'Should not include sort when nil'
    # Without filter, limit is automatically reduced to 2
    assert_equal 2, sent_body[:limit], 'Should limit to 2 records without filter'
    assert_equal 0, sent_body[:offset]
  end

  # Test response filtering - now returns plain text
  def test_client_list_records_filters_verbose_fields
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'rec_123',
          'title' => 'Test Record',
          'application_id' => 'app_123',
          'first_created' => {'on' => '2025-01-01', 'by' => 'user1'},
          'last_updated' => {'on' => '2025-01-02', 'by' => 'user2'},
          'description' => {
            'data' => {'huge' => 'nested structure'},
            'html' => '<p>Very long HTML content...</p>',
            'yjsData' => 'base64encodeddata...',
            'preview' => 'Short preview'
          },
          'comments_count' => 5,
          'ranking' => {'default' => 'abc123'},
          'custom_field' => 'Important data'
        }
      ],
      'total_count' => 1
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    # Providing fields parameter to pass validation
    result = client.list_records('tbl_123', 10, 0, fields: ['title'])

    # Result is now plain text string
    assert result.is_a?(String), 'Should return plain text string'

    # Should contain id and title
    assert_includes result, 'id: rec_123', 'Should include id'
    assert_includes result, 'title: Test Record', 'Should include title'

    # Should not contain verbose fields
    refute_includes result, 'description:', 'Should not include description'
    refute_includes result, 'comments_count:', 'Should not include comments_count'
    refute_includes result, 'ranking:', 'Should not include ranking'
  end

  def test_client_list_records_with_fields_parameter
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'rec_123',
          'title' => 'Test Record',
          'status' => 'active',
          'priority' => 5,
          'description' => 'Should be filtered',
          'custom_field' => 'Custom value'
        }
      ],
      'total_count' => 1
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_records('tbl_123', 10, 0, fields: ['status', 'priority'])

    # Result is now plain text string
    assert result.is_a?(String), 'Should return plain text string'

    # Check that requested fields are included in plain text
    assert_includes result, 'id: rec_123', 'Should include id (essential)'
    assert_includes result, 'title: Test Record', 'Should include title (essential)'
    assert_includes result, 'status: active', 'Should include status (requested)'
    assert_includes result, 'priority: 5', 'Should include priority (requested)'
    refute_includes result, 'description:', 'Should not include description'
  end

  def test_client_truncates_long_strings
    client = SmartSuiteClient.new('test_key', 'test_account')

    long_string = 'a' * 1000
    mock_response = {
      'items' => [
        {
          'id' => 'rec_123',
          'title' => 'Test',
          'long_field' => long_string
        }
      ],
      'total_count' => 1
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_records('tbl_123', 10, 0, fields: ['long_field'])

    # Result is now plain text string
    assert result.is_a?(String), 'Should return plain text string'

    # Check for truncation marker in plain text output
    assert_includes result, '...', 'Should truncate long strings in plain text'
    # The long string should be truncated (won't contain all 1000 'a's in sequence)
    refute_includes result, long_string, 'Should not include full long string'
  end

  def test_client_list_records_summary_only
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {'id' => 'rec_1', 'title' => 'Record 1', 'status' => 'active', 'priority' => 'high'},
        {'id' => 'rec_2', 'title' => 'Record 2', 'status' => 'active', 'priority' => 'low'},
        {'id' => 'rec_3', 'title' => 'Record 3', 'status' => 'pending', 'priority' => 'high'}
      ],
      'total_count' => 3
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_records('tbl_123', 10, 0, summary_only: true)

    # Should return summary structure
    assert result.key?(:summary), 'Should have summary'
    assert result.key?(:count), 'Should have count'
    assert result.key?(:total_count), 'Should have total_count'
    assert_equal 3, result[:count]
    assert_includes result[:summary], 'Found 3 records'
  end

  # Test tool call handling
  def test_handle_tool_call_get_api_stats
    # First track a call so stats aren't empty
    @server.instance_variable_get(:@stats_tracker).track_api_call(:get, '/test/')

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
    assert stats['summary']['total_calls'] >= 1
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

  def test_handle_tool_call_list_members
    # Mock the client list_members method
    client = @server.instance_variable_get(:@client)

    list_members_called = false

    client.define_singleton_method(:list_members) do |limit, offset, solution_id: nil|
      list_members_called = true
      {
        'members' => [
          {'id' => 'usr_1', 'title' => 'User One', 'email' => 'user1@example.com'},
          {'id' => 'usr_2', 'title' => 'User Two', 'email' => 'user2@example.com'}
        ],
        'count' => 2,
        'total_count' => 2
      }
    end

    request = {
      'id' => 9,
      'method' => 'tools/call',
      'params' => {
        'name' => 'list_members',
        'arguments' => {}
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 9, response['id']
    assert list_members_called, 'Should call list_members method'

    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 2, result['count']
    assert_equal 'usr_1', result['members'][0]['id']
  end

  def test_handle_tool_call_list_members_with_solution_filter
    # Mock the client list_members method
    client = @server.instance_variable_get(:@client)

    solution_id_param = nil

    client.define_singleton_method(:list_members) do |limit, offset, solution_id: nil|
      solution_id_param = solution_id
      {
        'members' => [
          {'id' => 'usr_1', 'title' => 'User One', 'email' => 'user1@example.com'}
        ],
        'count' => 1,
        'total_count' => 1,
        'filtered_by_solution' => solution_id
      }
    end

    request = {
      'id' => 10,
      'method' => 'tools/call',
      'params' => {
        'name' => 'list_members',
        'arguments' => {
          'solution_id' => 'sol_abc123'
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 10, response['id']
    assert_equal 'sol_abc123', solution_id_param, 'Should pass solution_id to client'

    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 1, result['count']
    assert_equal 'sol_abc123', result['filtered_by_solution']
  end

  # Test delete_record
  def test_client_delete_record
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what API call was made
    api_method = nil
    api_endpoint = nil
    mock_response = {'message' => 'Record deleted successfully'}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      mock_response
    end

    result = client.delete_record('tbl_123', 'rec_456')

    assert_equal :delete, api_method, 'Should use DELETE method'
    assert_equal '/applications/tbl_123/records/rec_456/', api_endpoint
    assert_equal 'Record deleted successfully', result['message']
  end

  def test_handle_tool_call_delete_record
    # Mock the client delete_record method
    client = @server.instance_variable_get(:@client)

    delete_called = false
    table_id_param = nil
    record_id_param = nil

    client.define_singleton_method(:delete_record) do |table_id, record_id|
      delete_called = true
      table_id_param = table_id
      record_id_param = record_id
      {'message' => 'Record deleted', 'id' => record_id}
    end

    request = {
      'id' => 8,
      'method' => 'tools/call',
      'params' => {
        'name' => 'delete_record',
        'arguments' => {
          'table_id' => 'tbl_test',
          'record_id' => 'rec_test'
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 8, response['id']
    assert delete_called, 'Should call delete_record method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 'rec_test', record_id_param

    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'Record deleted', result['message']
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
