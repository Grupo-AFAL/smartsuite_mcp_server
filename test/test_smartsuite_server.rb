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
    assert_includes tool_names, 'add_field'
    assert_includes tool_names, 'bulk_add_fields'
    assert_includes tool_names, 'update_field'
    assert_includes tool_names, 'delete_field'
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

    # Reset stats first to ensure clean slate (previous tests may have left data)
    tracker.reset_stats

    stats = tracker.get_stats

    assert_equal 0, stats['summary']['total_calls']
    assert_equal 0, stats['summary']['unique_users']
    assert_equal 0, stats['summary']['unique_solutions']
    assert_equal 0, stats['summary']['unique_tables']
  end

  def test_stats_tracker_tracks_calls
    tracker = ApiStatsTracker.new('test_key')

    # Reset stats first to ensure clean slate (important if real-world testing was done)
    tracker.reset_stats

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

    result = client.list_solutions(bypass_cache: true)

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

    result = client.list_solutions(bypass_cache: true)

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

    result = client.list_tables(bypass_cache: true)

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
    result = client.list_tables(solution_id: 'sol_1', bypass_cache: true)

    # Verify the API was called with the solution query parameter
    assert_equal '/applications/?solution=sol_1', called_endpoint, 'Should use solution query parameter'

    # Verify response
    assert_equal 2, result['count'], 'Should return only tables from sol_1'
    assert_equal 'tbl_1', result['tables'][0]['id']
    assert_equal 'tbl_2', result['tables'][1]['id']
  end

  def test_client_list_tables_with_fields_parameter
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track the endpoint that was called
    called_endpoint = nil

    # Mock response - API returns requested fields
    mock_response = {
      'items' => [
        {
          'id' => 'tbl_1',
          'name' => 'Table 1',
          'structure' => [{'slug' => 'field1', 'label' => 'Field 1'}],
          'solution_id' => 'sol_1'
        }
      ]
    }

    # Mock the api_request method to track endpoint
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test with fields parameter
    result = client.list_tables(fields: ['name', 'id', 'structure'], bypass_cache: true)

    # Verify the API was called with fields query parameters
    assert_includes called_endpoint, 'fields=name', 'Should include fields=name'
    assert_includes called_endpoint, 'fields=id', 'Should include fields=id'
    assert_includes called_endpoint, 'fields=structure', 'Should include fields=structure'

    # Verify response includes all fields (not client-filtered)
    assert_equal 1, result['count']
    assert result['tables'][0].key?('structure'), 'Should include structure field when explicitly requested'
    assert_equal 'Table 1', result['tables'][0]['name']
  end

  def test_client_list_tables_with_solution_and_fields
    client = SmartSuiteClient.new('test_key', 'test_account')

    called_endpoint = nil
    mock_response = {'items' => []}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test with both solution_id and fields
    client.list_tables(solution_id: 'sol_123', fields: ['name', 'id'])

    # Verify both parameters are in the endpoint
    assert_includes called_endpoint, 'solution=sol_123', 'Should include solution parameter'
    assert_includes called_endpoint, 'fields=name', 'Should include fields parameter'
    assert_includes called_endpoint, 'fields=id', 'Should include fields parameter'
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
          'email' => 'john@example.com',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          },
          'job_title' => 'Developer',
          'department' => 'Engineering',
          'role' => 'admin',
          'status' => 'active',
          'extra_field' => 'should be filtered'
        },
        {
          'id' => 'usr_456',
          'email' => 'jane@example.com',
          'full_name' => {
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'sys_root' => 'Jane Smith'
          },
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
    assert_equal 'John Doe', result['members'][0]['full_name']
    assert_equal 'John', result['members'][0]['first_name']
    assert_equal 'Doe', result['members'][0]['last_name']
    assert_equal 'john@example.com', result['members'][0]['email']
    assert_equal 'Developer', result['members'][0]['job_title']
    assert_equal 'Engineering', result['members'][0]['department']
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
          'email' => 'john@example.com',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          },
          'job_title' => 'Developer'
        },
        {
          'id' => 'usr_456',
          'email' => 'jane@example.com',
          'full_name' => {
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'sys_root' => 'Jane Smith'
          }
        },
        {
          'id' => 'usr_789',
          'email' => 'bob@example.com',
          'full_name' => {
            'first_name' => 'Bob',
            'last_name' => 'Wilson',
            'sys_root' => 'Bob Wilson'
          }
        },
        {
          'id' => 'usr_999',
          'email' => 'alice@example.com',
          'full_name' => {
            'first_name' => 'Alice',
            'last_name' => 'Brown',
            'sys_root' => 'Alice Brown'
          }
        },
        {
          'id' => 'usr_000',
          'email' => 'not@example.com',
          'full_name' => {
            'first_name' => 'Not',
            'last_name' => 'InSolution',
            'sys_root' => 'Not InSolution'
          }
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
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Track what endpoint and body were sent
    sent_endpoint = nil
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    filter = {
      'operator' => 'and',
      'fields' => [
        {'field' => 'status', 'comparison' => 'is', 'value' => 'active'}
      ]
    }
    client.list_records('tbl_123', 10, 0, filter: filter, fields: ['status'])

    # Filter should be in body
    assert_equal filter, sent_body[:filter]
    # limit and offset should be in query params
    assert_includes sent_endpoint, '?limit=10&offset=0', 'Should have limit and offset as query params'
  end

  def test_client_list_records_with_sort
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Track what endpoint and body were sent
    sent_endpoint = nil
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    sort = [{'field' => 'created_on', 'direction' => 'desc'}]
    client.list_records('tbl_123', 10, 0, sort: sort, fields: ['status'])

    # Sort should be in body
    assert_equal sort, sent_body[:sort]
    # Explicit limit should be respected (no longer auto-reduced)
    assert_includes sent_endpoint, '?limit=10&offset=0', 'Should respect explicitly specified limit'
  end

  def test_client_list_records_with_filter_and_sort
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Track what endpoint and body were sent
    sent_endpoint = nil
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_endpoint = endpoint
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

    # Filter and sort should be in body
    assert_equal filter, sent_body[:filter]
    assert_equal sort, sent_body[:sort]
    # limit and offset should be in query params
    assert_includes sent_endpoint, '?limit=20&offset=10', 'Should have limit and offset as query params'
  end

  def test_client_list_records_without_filter_or_sort
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Track what endpoint and body were sent
    sent_endpoint = nil
    sent_body = nil
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      {'items' => [], 'total_count' => 0}
    end

    client.list_records('tbl_123', 50, 0, fields: ['status'])

    # Body should be nil or empty when no filter or sort
    assert sent_body.nil? || sent_body.empty?, 'Body should be nil or empty when no filter/sort'
    # Explicit limit should be respected (no longer auto-reduced)
    assert_includes sent_endpoint, '?limit=50&offset=0', 'Should respect explicitly specified limit'
  end

  # Test response filtering - now returns plain text
  def test_client_list_records_filters_verbose_fields
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

  def test_client_returns_full_field_values
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    # Should NOT truncate - should include full long string
    assert_includes result, long_string, 'Should include full long string (no truncation)'
  end

  # Test tool call handling
  def test_handle_tool_call_get_api_stats
    # First track a call so stats aren't empty
    @server.instance_variable_get(:@client).stats_tracker.track_api_call(:get, '/test/')

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

  # Test field operations
  def test_client_add_field
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Track what API call was made
    api_method = nil
    api_endpoint = nil
    api_body = nil
    mock_response = {
      'slug' => 'test_field',
      'label' => 'Test Field',
      'field_type' => 'textfield'
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    field_data = {
      'slug' => 'test_field',
      'label' => 'Test Field',
      'field_type' => 'textfield',
      'is_new' => true
    }

    result = client.add_field('tbl_123', field_data)

    assert_equal :post, api_method, 'Should use POST method'
    assert_equal '/applications/tbl_123/add_field/', api_endpoint
    assert_equal field_data, api_body['field']
    assert_equal true, api_body['auto_fill_structure_layout']
    assert_equal 'Test Field', result['label']
  end

  def test_handle_tool_call_add_field
    client = @server.instance_variable_get(:@client)

    add_field_called = false
    table_id_param = nil
    field_data_param = nil

    client.define_singleton_method(:add_field) do |table_id, field_data, field_position: nil, auto_fill_structure_layout: true|
      add_field_called = true
      table_id_param = table_id
      field_data_param = field_data
      {'slug' => field_data['slug'], 'label' => field_data['label']}
    end

    request = {
      'id' => 11,
      'method' => 'tools/call',
      'params' => {
        'name' => 'add_field',
        'arguments' => {
          'table_id' => 'tbl_test',
          'field_data' => {
            'slug' => 'new_field',
            'label' => 'New Field',
            'field_type' => 'textfield'
          }
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 11, response['id']
    assert add_field_called, 'Should call add_field method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 'new_field', field_data_param['slug']
  end

  def test_client_bulk_add_fields
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_method = nil
    api_endpoint = nil
    api_body = nil
    mock_response = {'success' => true}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    fields = [
      {'slug' => 'field1', 'label' => 'Field 1', 'field_type' => 'textfield', 'is_new' => true},
      {'slug' => 'field2', 'label' => 'Field 2', 'field_type' => 'numberfield', 'is_new' => true}
    ]

    result = client.bulk_add_fields('tbl_123', fields)

    assert_equal :post, api_method, 'Should use POST method'
    assert_equal '/applications/tbl_123/bulk-add-fields/', api_endpoint
    assert_equal fields, api_body['fields']
    assert_equal true, result['success']
  end

  def test_handle_tool_call_bulk_add_fields
    client = @server.instance_variable_get(:@client)

    bulk_add_called = false
    table_id_param = nil
    fields_param = nil

    client.define_singleton_method(:bulk_add_fields) do |table_id, fields, set_as_visible_fields_in_reports: nil|
      bulk_add_called = true
      table_id_param = table_id
      fields_param = fields
      {'success' => true, 'count' => fields.length}
    end

    request = {
      'id' => 12,
      'method' => 'tools/call',
      'params' => {
        'name' => 'bulk_add_fields',
        'arguments' => {
          'table_id' => 'tbl_test',
          'fields' => [
            {'slug' => 'f1', 'label' => 'Field 1'},
            {'slug' => 'f2', 'label' => 'Field 2'}
          ]
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 12, response['id']
    assert bulk_add_called, 'Should call bulk_add_fields method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 2, fields_param.length
  end

  def test_client_update_field
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_method = nil
    api_endpoint = nil
    api_body = nil
    mock_response = {'slug' => 'test_field', 'label' => 'Updated Label'}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    field_data = {'label' => 'Updated Label', 'field_type' => 'textfield'}
    result = client.update_field('tbl_123', 'test_field', field_data)

    assert_equal :put, api_method, 'Should use PUT method'
    assert_equal '/applications/tbl_123/change_field/', api_endpoint
    assert_equal 'test_field', api_body['slug']
    assert_equal 'Updated Label', api_body['label']
    assert_equal 'Updated Label', result['label']
  end

  def test_handle_tool_call_update_field
    client = @server.instance_variable_get(:@client)

    update_called = false
    table_id_param = nil
    slug_param = nil
    field_data_param = nil

    client.define_singleton_method(:update_field) do |table_id, slug, field_data|
      update_called = true
      table_id_param = table_id
      slug_param = slug
      field_data_param = field_data
      {'slug' => slug, 'label' => field_data['label']}
    end

    request = {
      'id' => 13,
      'method' => 'tools/call',
      'params' => {
        'name' => 'update_field',
        'arguments' => {
          'table_id' => 'tbl_test',
          'slug' => 'field_slug',
          'field_data' => {'label' => 'New Label'}
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 13, response['id']
    assert update_called, 'Should call update_field method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 'field_slug', slug_param
    assert_equal 'New Label', field_data_param['label']
  end

  def test_client_delete_field
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_method = nil
    api_endpoint = nil
    api_body = nil
    mock_response = {'slug' => 'deleted_field', 'label' => 'Deleted Field'}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    result = client.delete_field('tbl_123', 'deleted_field')

    assert_equal :post, api_method, 'Should use POST method'
    assert_equal '/applications/tbl_123/delete_field/', api_endpoint
    assert_equal 'deleted_field', api_body['slug']
    assert_equal 'Deleted Field', result['label']
  end

  def test_handle_tool_call_delete_field
    client = @server.instance_variable_get(:@client)

    delete_called = false
    table_id_param = nil
    slug_param = nil

    client.define_singleton_method(:delete_field) do |table_id, slug|
      delete_called = true
      table_id_param = table_id
      slug_param = slug
      {'slug' => slug, 'deleted' => true}
    end

    request = {
      'id' => 14,
      'method' => 'tools/call',
      'params' => {
        'name' => 'delete_field',
        'arguments' => {
          'table_id' => 'tbl_test',
          'slug' => 'field_to_delete'
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 14, response['id']
    assert delete_called, 'Should call delete_field method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 'field_to_delete', slug_param
  end

  # Test view operations
  def test_client_get_view_records
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_method = nil
    api_endpoint = nil
    mock_response = {
      'records' => [
        {'id' => 'rec_1', 'title' => 'Record 1', 'status' => 'approved'},
        {'id' => 'rec_2', 'title' => 'Record 2', 'status' => 'approved'}
      ],
      'total_records_count' => 2,
      'filter' => {'operator' => 'and', 'fields' => []}
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      mock_response
    end

    result = client.get_view_records('tbl_123', 'view_456')

    assert_equal :get, api_method, 'Should use GET method'
    assert_equal '/applications/tbl_123/records-for-report/?report=view_456', api_endpoint
    assert_equal 2, result['records'].length
    assert_equal 'rec_1', result['records'][0]['id']
  end

  def test_client_get_view_records_with_empty_values
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_endpoint = nil
    mock_response = {'records' => [], 'total_records_count' => 0}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_endpoint = endpoint
      mock_response
    end

    client.get_view_records('tbl_123', 'view_456', with_empty_values: true)

    assert_includes api_endpoint, 'with_empty_values=true', 'Should include with_empty_values parameter'
  end

  def test_handle_tool_call_get_view_records
    client = @server.instance_variable_get(:@client)

    get_view_called = false
    table_id_param = nil
    view_id_param = nil

    client.define_singleton_method(:get_view_records) do |table_id, view_id, with_empty_values: false|
      get_view_called = true
      table_id_param = table_id
      view_id_param = view_id
      {
        'records' => [
          {'id' => 'rec_1', 'title' => 'Test Record'}
        ],
        'total_records_count' => 1
      }
    end

    request = {
      'id' => 15,
      'method' => 'tools/call',
      'params' => {
        'name' => 'get_view_records',
        'arguments' => {
          'table_id' => 'tbl_test',
          'view_id' => 'view_test'
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 15, response['id']
    assert get_view_called, 'Should call get_view_records method'
    assert_equal 'tbl_test', table_id_param
    assert_equal 'view_test', view_id_param
  end

  def test_client_create_view
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_method = nil
    api_endpoint = nil
    api_body = nil
    mock_response = {
      'id' => 'view_789',
      'label' => 'Test View',
      'view_mode' => 'grid',
      'application' => 'tbl_123',
      'solution' => 'sol_456',
      'is_private' => false,
      'state' => {
        'filterWindow' => {
          'opened' => false,
          'filter' => {
            'operator' => 'and',
            'fields' => []
          }
        }
      }
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    result = client.create_view(
      'tbl_123',
      'sol_456',
      'Test View',
      'grid',
      is_private: false
    )

    assert_equal :post, api_method, 'Should use POST method'
    assert_equal '/reports/', api_endpoint
    assert_equal 'tbl_123', api_body['application']
    assert_equal 'sol_456', api_body['solution']
    assert_equal 'Test View', api_body['label']
    assert_equal 'grid', api_body['view_mode']
    assert_equal false, api_body['is_private']
    assert_equal 'view_789', result['id']
  end

  def test_client_create_view_with_filter_state
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_body = nil
    mock_response = {'id' => 'view_123', 'label' => 'Filtered View'}

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_body = body
      mock_response
    end

    filter_state = {
      'filterWindow' => {
        'opened' => false,
        'filter' => {
          'operator' => 'and',
          'fields' => [
            {'field' => 'status', 'comparison' => 'is', 'value' => 'approved'}
          ]
        }
      }
    }

    result = client.create_view(
      'tbl_123',
      'sol_456',
      'Filtered View',
      'grid',
      state: filter_state
    )

    assert_equal filter_state, api_body['state'], 'Should include filter state'
    assert_equal 'Filtered View', result['label']
  end

  def test_handle_tool_call_create_view
    client = @server.instance_variable_get(:@client)

    create_view_called = false
    application_param = nil
    solution_param = nil
    label_param = nil
    view_mode_param = nil
    state_param = nil

    client.define_singleton_method(:create_view) do |application, solution, label, view_mode, **options|
      create_view_called = true
      application_param = application
      solution_param = solution
      label_param = label
      view_mode_param = view_mode
      state_param = options[:state]
      {
        'id' => 'view_new',
        'label' => label,
        'view_mode' => view_mode,
        'state' => options[:state]
      }
    end

    request = {
      'id' => 16,
      'method' => 'tools/call',
      'params' => {
        'name' => 'create_view',
        'arguments' => {
          'application' => 'tbl_test',
          'solution' => 'sol_test',
          'label' => 'New View',
          'view_mode' => 'kanban',
          'state' => {
            'filterWindow' => {
              'opened' => false,
              'filter' => {
                'operator' => 'and',
                'fields' => [
                  {'field' => 'priority', 'comparison' => 'is', 'value' => 'high'}
                ]
              }
            }
          }
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 16, response['id']
    assert create_view_called, 'Should call create_view method'
    assert_equal 'tbl_test', application_param
    assert_equal 'sol_test', solution_param
    assert_equal 'New View', label_param
    assert_equal 'kanban', view_mode_param
    assert state_param, 'Should pass state parameter'
    assert_equal 'and', state_param['filterWindow']['filter']['operator']
  end

  def test_tools_list_includes_view_operations
    request = {
      'id' => 17,
      'method' => 'tools/list',
      'params' => {}
    }

    response = call_private_method(:handle_tools_list, request)

    tool_names = response['result']['tools'].map { |t| t['name'] }
    assert_includes tool_names, 'get_view_records', 'Should include get_view_records tool'
    assert_includes tool_names, 'create_view', 'Should include create_view tool'
  end

  # Test list_solutions_by_owner
  def test_list_solutions_by_owner_filters_by_owner
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'logo_icon' => 'star',
          'logo_color' => '#FF0000',
          'permissions' => {
            'owners' => ['user_123', 'user_456']
          }
        },
        {
          'id' => 'sol_2',
          'name' => 'Solution 2',
          'logo_icon' => 'heart',
          'logo_color' => '#00FF00',
          'permissions' => {
            'owners' => ['user_789']
          }
        },
        {
          'id' => 'sol_3',
          'name' => 'Solution 3',
          'logo_icon' => 'circle',
          'logo_color' => '#0000FF',
          'permissions' => {
            'owners' => ['user_123']
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123')

    assert_equal 2, result['count'], 'Should return 2 solutions owned by user_123'
    assert_equal 2, result['solutions'].length
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'sol_3', result['solutions'][1]['id']
    assert_equal 'Solution 1', result['solutions'][0]['name']
    assert_equal 'Solution 3', result['solutions'][1]['name']
  end

  def test_list_solutions_by_owner_with_activity_data
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'logo_icon' => 'star',
          'logo_color' => '#FF0000',
          'permissions' => {
            'owners' => ['user_123']
          },
          'status' => 'active',
          'last_access' => '2025-01-01T00:00:00Z',
          'records_count' => 100,
          'applications_count' => 5
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123', include_activity_data: true)

    assert_equal 1, result['count']
    solution = result['solutions'][0]
    assert_equal 'active', solution['status']
    assert_equal '2025-01-01T00:00:00Z', solution['last_access']
    assert_equal 100, solution['records_count']
    assert_equal 5, solution['applications_count']
  end

  def test_list_solutions_by_owner_returns_empty_when_no_matches
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'permissions' => {
            'owners' => ['user_789']
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123')

    assert_equal 0, result['count']
    assert_equal 0, result['solutions'].length
  end

  def test_tools_list_includes_list_solutions_by_owner
    request = {
      'id' => 18,
      'method' => 'tools/list',
      'params' => {}
    }

    response = call_private_method(:handle_tools_list, request)

    tool_names = response['result']['tools'].map { |t| t['name'] }
    assert_includes tool_names, 'list_solutions_by_owner', 'Should include list_solutions_by_owner tool'

    tool = response['result']['tools'].find { |t| t['name'] == 'list_solutions_by_owner' }
    assert tool['inputSchema']['properties']['owner_id'], 'Should have owner_id parameter'
    assert tool['inputSchema']['properties']['include_activity_data'], 'Should have include_activity_data parameter'
    assert_equal ['owner_id'], tool['inputSchema']['required'], 'owner_id should be required'
  end

  # Test get_solution_most_recent_record_update
  def test_get_solution_most_recent_record_update_returns_latest_date
    client = SmartSuiteClient.new('test_key', 'test_account')

    # Mock responses
    mock_tables_response = {
      'tables' => [
        {'id' => 'tbl_1', 'name' => 'Table 1'},
        {'id' => 'tbl_2', 'name' => 'Table 2'}
      ],
      'count' => 2
    }

    mock_records_responses = {
      'tbl_1' => {
        'items' => [
          {
            'last_updated' => {
              'on' => '2025-01-10T12:00:00Z'
            }
          }
        ]
      },
      'tbl_2' => {
        'items' => [
          {
            'last_updated' => {
              'on' => '2025-01-15T12:00:00Z'
            }
          }
        ]
      }
    }

    client.define_singleton_method(:list_tables) do |solution_id: nil|
      mock_tables_response
    end

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      # Extract table_id from endpoint like "/applications/tbl_1/records/list/?limit=1&offset=0"
      if endpoint.include?('/records/list/')
        table_id = endpoint.match(/applications\/([^\/]+)\/records/)[1]
        mock_records_responses[table_id]
      end
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_equal '2025-01-15T12:00:00Z', result, 'Should return the most recent date across all tables'
  end

  def test_get_solution_most_recent_record_update_returns_nil_when_no_records
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_tables_response = {
      'tables' => [
        {'id' => 'tbl_1', 'name' => 'Table 1'}
      ],
      'count' => 1
    }

    client.define_singleton_method(:list_tables) do |solution_id: nil|
      mock_tables_response
    end

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      {'items' => []}
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_nil result, 'Should return nil when no records exist'
  end

  def test_get_solution_most_recent_record_update_returns_nil_when_no_tables
    client = SmartSuiteClient.new('test_key', 'test_account')

    client.define_singleton_method(:list_tables) do |solution_id: nil|
      {'tables' => [], 'count' => 0}
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_nil result, 'Should return nil when solution has no tables'
  end

  # Test search_member
  def test_search_member_finds_by_email
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'john.doe@example.com',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        },
        {
          'id' => 'user_2',
          'email' => 'jane.smith@example.com',
          'role' => 'member',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'sys_root' => 'Jane Smith'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('john.doe')

    assert_equal 1, result['count'], 'Should find 1 member by email'
    assert_equal 'john.doe', result['query']
    assert_equal 'user_1', result['members'][0]['id']
    assert_equal 'john.doe@example.com', result['members'][0]['email']
  end

  def test_search_member_finds_by_first_name
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'john.doe@example.com',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        },
        {
          'id' => 'user_2',
          'email' => 'jane.smith@example.com',
          'role' => 'member',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'sys_root' => 'Jane Smith'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('jane')

    assert_equal 1, result['count'], 'Should find 1 member by first name'
    assert_equal 'user_2', result['members'][0]['id']
    assert_equal 'Jane', result['members'][0]['first_name']
  end

  def test_search_member_finds_by_last_name
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'john.doe@example.com',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('doe')

    assert_equal 1, result['count'], 'Should find 1 member by last name'
    assert_equal 'user_1', result['members'][0]['id']
    assert_equal 'Doe', result['members'][0]['last_name']
  end

  def test_search_member_is_case_insensitive
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'John.Doe@Example.COM',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('JOHN')

    assert_equal 1, result['count'], 'Should be case insensitive'
    assert_equal 'user_1', result['members'][0]['id']
  end

  def test_search_member_returns_empty_when_no_matches
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'john.doe@example.com',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('nonexistent')

    assert_equal 0, result['count'], 'Should return 0 when no matches'
    assert_equal 0, result['members'].length
  end

  def test_search_member_handles_email_array
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => ['john.doe@example.com', 'j.doe@example.com'],
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          }
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('john.doe')

    assert_equal 1, result['count'], 'Should handle email as array'
    assert_equal 'user_1', result['members'][0]['id']
  end

  def test_search_member_includes_optional_fields
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'user_1',
          'email' => 'john.doe@example.com',
          'role' => 'admin',
          'status' => 'active',
          'full_name' => {
            'first_name' => 'John',
            'last_name' => 'Doe',
            'sys_root' => 'John Doe'
          },
          'job_title' => 'Senior Developer',
          'department' => 'Engineering'
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.search_member('john')

    assert_equal 1, result['count']
    member = result['members'][0]
    assert_equal 'Senior Developer', member['job_title']
    assert_equal 'Engineering', member['department']
  end

  def test_tools_list_includes_search_member
    request = {
      'id' => 19,
      'method' => 'tools/list',
      'params' => {}
    }

    response = call_private_method(:handle_tools_list, request)

    tool_names = response['result']['tools'].map { |t| t['name'] }
    assert_includes tool_names, 'search_member', 'Should include search_member tool'

    tool = response['result']['tools'].find { |t| t['name'] == 'search_member' }
    assert tool['inputSchema']['properties']['query'], 'Should have query parameter'
    assert_equal ['query'], tool['inputSchema']['required'], 'query should be required'
  end

  # Test list_solutions with fields parameter
  def test_list_solutions_with_fields_parameter
    client = SmartSuiteClient.new('test_key', 'test_account')

    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'created' => '2025-01-01T00:00:00Z',
          'created_by' => 'user_123',
          'logo_icon' => 'star',
          'logo_color' => '#FF0000',
          'extra_field' => 'should not be included'
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions(fields: ['id', 'name', 'created'])

    assert_equal 1, result['count']
    solution = result['solutions'][0]
    assert_equal 'sol_1', solution['id']
    assert_equal 'Solution 1', solution['name']
    assert_equal '2025-01-01T00:00:00Z', solution['created']
    refute solution.key?('logo_icon'), 'Should not include fields not requested'
    refute solution.key?('extra_field'), 'Should not include extra fields'
  end

  def test_list_solutions_without_fields_returns_essential_only
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    mock_response = {
      'items' => [
        {
          'id' => 'sol_1',
          'name' => 'Solution 1',
          'logo_icon' => 'star',
          'logo_color' => '#FF0000',
          'created' => '2025-01-01T00:00:00Z',
          'status' => 'active'
        }
      ]
    }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      mock_response
    end

    result = client.list_solutions

    assert_equal 1, result['count']
    solution = result['solutions'][0]
    assert_equal 'sol_1', solution['id']
    assert_equal 'Solution 1', solution['name']
    assert_equal 'star', solution['logo_icon']
    assert_equal '#FF0000', solution['logo_color']
    refute solution.key?('created'), 'Should not include non-essential fields by default'
    refute solution.key?('status'), 'Should not include activity fields by default'
  end

  # Test cache integration
  def test_client_initializes_with_cache_enabled_by_default
    # Use a temporary cache path for testing
    cache_path = File.join(Dir.tmpdir, "test_cache_#{Time.now.to_i}.db")

    begin
      client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: true, cache_path: cache_path)

      assert client.cache_enabled?, 'Cache should be enabled by default'
      refute_nil client.cache, 'Cache object should be initialized'
    ensure
      # Clean up test cache file
      File.delete(cache_path) if File.exist?(cache_path)
    end
  end

  def test_client_initializes_without_cache_when_disabled
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    refute client.cache_enabled?, 'Cache should be disabled when cache_enabled: false'
    assert_nil client.cache, 'Cache object should be nil when disabled'
  end

  def test_list_records_uses_cache_when_enabled
    cache_path = File.join(Dir.tmpdir, "test_cache_#{Time.now.to_i}.db")

    begin
      client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: true, cache_path: cache_path)

      # Track API calls
      api_call_count = 0

      # Mock get_table (for structure)
      client.define_singleton_method(:get_table) do |table_id|
        api_call_count += 1
        {
          'id' => table_id,
          'name' => 'Test Table',
          'structure' => [
            {'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield'},
            {'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield'}
          ]
        }
      end

      # Mock fetch_all_records (for cache population)
      client.define_singleton_method(:fetch_all_records) do |table_id|
        api_call_count += 1
        [
          {'id' => 'rec_1', 'title' => 'Record 1', 'status' => 'active'},
          {'id' => 'rec_2', 'title' => 'Record 2', 'status' => 'pending'}
        ]
      end

      # First call should populate cache (2 API calls: get_table + fetch_all_records)
      result1 = client.list_records('tbl_123', 10, 0, fields: ['title', 'status'])
      assert_equal 2, api_call_count, 'Should make 2 API calls to populate cache'

      # Second call should use cache (no additional API calls)
      result2 = client.list_records('tbl_123', 5, 0, fields: ['title'])
      assert_equal 2, api_call_count, 'Should not make additional API calls (cache hit)'

      # Both results should be plain text
      assert result1.is_a?(String), 'Should return plain text'
      assert result2.is_a?(String), 'Should return plain text'
    ensure
      File.delete(cache_path) if File.exist?(cache_path)
    end
  end

  def test_list_records_bypasses_cache_when_disabled
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    api_call_count = 0

    # Mock api_request for direct API calls
    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_call_count += 1
      {'items' => [], 'total_count' => 0}
    end

    # Each call should hit the API
    client.list_records('tbl_123', 10, 0, fields: ['title'])
    assert_equal 1, api_call_count, 'Should make 1 API call'

    client.list_records('tbl_123', 10, 0, fields: ['title'])
    assert_equal 2, api_call_count, 'Should make another API call (no cache)'
  end

  def test_list_records_with_bypass_cache_parameter
    cache_path = File.join(Dir.tmpdir, "test_cache_#{Time.now.to_i}.db")

    begin
      client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: true, cache_path: cache_path)

      api_call_count = 0

      # Mock api_request for direct API calls
      client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
        api_call_count += 1
        {'items' => [], 'total_count' => 0}
      end

      # Call with bypass_cache should always hit API
      client.list_records('tbl_123', 10, 0, fields: ['title'], bypass_cache: true)
      assert_equal 1, api_call_count, 'Should make API call when bypass_cache: true'

      client.list_records('tbl_123', 10, 0, fields: ['title'], bypass_cache: true)
      assert_equal 2, api_call_count, 'Should make another API call when bypass_cache: true'
    ensure
      File.delete(cache_path) if File.exist?(cache_path)
    end
  end
end
