# frozen_string_literal: true

require_relative 'test_helper'
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
    FileUtils.rm_f(stats_file)
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
    assert prompts.length.positive?, 'Should return at least one prompt'

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
    assert_equal(-32_601, response['error']['code'])
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
    assert tracker.get_stats['summary']['total_calls'].positive?

    # Reset stats
    result = tracker.reset_stats
    assert_equal 'success', result['status']

    # Verify stats are reset
    assert_equal 0, tracker.get_stats['summary']['total_calls']
  end

  # Test SmartSuiteClient data formatting
  def test_client_list_solutions_formats_hash_response
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions(format: :json)

    assert_equal 2, result['count']
    assert_equal 2, result['solutions'].length
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'Solution 1', result['solutions'][0]['name']
    refute result['solutions'][0].key?('extra_field'), 'Should filter out extra fields'
  end

  def test_client_list_solutions_formats_array_response
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    mock_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution 1',
        'logo_icon' => 'star',
        'logo_color' => '#FF0000'
      }
    ]

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions(format: :json)

    assert_equal 1, result['count']
    assert_equal 1, result['solutions'].length
  end

  def test_client_list_tables_formats_response
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_tables(format: :json)

    assert_equal 1, result['count']
    assert_equal 'tbl_1', result['tables'][0]['id']
    assert_equal 'Table 1', result['tables'][0]['name']
    assert_equal 'sol_1', result['tables'][0]['solution_id']
    refute result['tables'][0].key?('structure'), 'Should filter out structure field'
  end

  def test_client_list_tables_filters_by_solution_id
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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
    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test filtering by solution_id
    result = client.list_tables(solution_id: 'sol_1', format: :json)

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
          'structure' => [{ 'slug' => 'field1', 'label' => 'Field 1' }],
          'solution_id' => 'sol_1'
        }
      ]
    }

    # Mock the api_request method to track endpoint
    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test with fields parameter
    result = client.list_tables(fields: %w[name id structure], format: :json)

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
    mock_response = { 'items' => [] }

    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      called_endpoint = endpoint
      mock_response
    end

    # Test with both solution_id and fields
    client.list_tables(solution_id: 'sol_123', fields: %w[name id], format: :json)

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
          { 'access' => 'full_access', 'entity' => 'usr_1' },
          { 'access' => 'assignee', 'entity' => 'usr_2' }
        ],
        'owners' => ['usr_3']
      }
    }

    # Mock the api_request method
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.get_solution('sol_123')

    assert_equal 'sol_123', result['id']
    assert_equal 'Test Solution', result['name']
    assert result['permissions']
    assert result['permissions']['members']
  end

  def test_client_list_members
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_members(format: :json)

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
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Mock solution response with permissions structure (includes team)
    mock_solution = {
      'id' => 'sol_123',
      'name' => 'Test Solution',
      'permissions' => {
        'members' => [
          { 'access' => 'full_access', 'entity' => 'usr_123' }
        ],
        'owners' => ['usr_789'],
        'teams' => [
          { 'access' => 'full_access', 'entity' => 'team_001' }
        ]
      }
    }

    # Mock team response
    mock_team = {
      'id' => 'team_001',
      'name' => 'Test Team',
      'members' => %w[usr_456 usr_999]
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
    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      if endpoint.include?('/solutions/')
        mock_solution
      elsif endpoint.include?('/teams/list/')
        mock_teams_list
      else
        mock_members
      end
    end

    result = client.list_members(limit: 100, offset: 0, solution_id: 'sol_123', format: :json)

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
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.get_table('tbl_123', format: :json)

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
    client.define_singleton_method(:api_request) do |_method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      { 'items' => [], 'total_count' => 0 }
    end

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'active' }
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
    client.define_singleton_method(:api_request) do |_method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      { 'items' => [], 'total_count' => 0 }
    end

    sort = [{ 'field' => 'created_on', 'direction' => 'desc' }]
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
    client.define_singleton_method(:api_request) do |_method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      { 'items' => [], 'total_count' => 0 }
    end

    filter = {
      'operator' => 'and',
      'fields' => [
        { 'field' => 'status', 'comparison' => 'is', 'value' => 'active' },
        { 'field' => 'priority', 'comparison' => 'is_greater_than', 'value' => 3 }
      ]
    }
    sort = [{ 'field' => 'created_on', 'direction' => 'desc' }, { 'field' => 'title', 'direction' => 'asc' }]
    client.list_records('tbl_123', 20, 10, filter: filter, sort: sort, fields: %w[status priority])

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
    client.define_singleton_method(:api_request) do |_method, endpoint, body = nil|
      sent_endpoint = endpoint
      sent_body = body
      { 'items' => [], 'total_count' => 0 }
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
          'first_created' => { 'on' => '2025-01-01', 'by' => 'user1' },
          'last_updated' => { 'on' => '2025-01-02', 'by' => 'user2' },
          'description' => {
            'data' => { 'huge' => 'nested structure' },
            'html' => '<p>Very long HTML content...</p>',
            'yjsData' => 'base64encodeddata...',
            'preview' => 'Short preview'
          },
          'comments_count' => 5,
          'ranking' => { 'default' => 'abc123' },
          'custom_field' => 'Important data'
        }
      ],
      'total_count' => 1
    }

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    # Providing fields parameter to pass validation
    result = client.list_records('tbl_123', 10, 0, fields: ['title'])

    # Result is now TOON format string
    assert result.is_a?(String), 'Should return TOON format string'

    # Should contain id and title (TOON uses tabular format)
    assert_includes result, 'rec_123', 'Should include id'
    assert_includes result, 'Test Record', 'Should include title'

    # Should not contain verbose fields (not requested)
    refute_includes result, 'description', 'Should not include description field in header'
    refute_includes result, 'comments_count', 'Should not include comments_count'
    refute_includes result, 'ranking', 'Should not include ranking'
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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_records('tbl_123', 10, 0, fields: %w[status priority])

    # Result is now TOON format string
    assert result.is_a?(String), 'Should return TOON format string'

    # Check that requested fields are included in TOON tabular format
    assert_includes result, 'rec_123', 'Should include id (essential)'
    assert_includes result, 'Test Record', 'Should include title (essential)'
    assert_includes result, 'active', 'Should include status value (requested)'
    assert_includes result, '5', 'Should include priority value (requested)'
    refute_includes result, 'description', 'Should not include description field'
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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
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
    assert_equal(-32_602, response['error']['code'])
    assert_match(/Unknown tool/, response['error']['message'])
  end

  def test_handle_tool_call_list_members
    # Mock the client list_members method
    client = @server.instance_variable_get(:@client)

    list_members_called = false

    client.define_singleton_method(:list_members) do |limit: 100, offset: 0, solution_id: nil, include_inactive: false, format: :toon|
      list_members_called = true
      {
        'members' => [
          { 'id' => 'usr_1', 'title' => 'User One', 'email' => 'user1@example.com' },
          { 'id' => 'usr_2', 'title' => 'User Two', 'email' => 'user2@example.com' }
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

    client.define_singleton_method(:list_members) do |limit: 100, offset: 0, solution_id: nil, include_inactive: false, format: :toon|
      solution_id_param = solution_id
      {
        'members' => [
          { 'id' => 'usr_1', 'title' => 'User One', 'email' => 'user1@example.com' }
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
    mock_response = { 'message' => 'Record deleted successfully' }

    client.define_singleton_method(:api_request) do |method, endpoint, _body = nil|
      api_method = method
      api_endpoint = endpoint
      mock_response
    end

    result = client.delete_record('tbl_123', 'rec_456', minimal_response: false, format: :json)

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

    client.define_singleton_method(:delete_record) do |table_id, record_id, minimal_response: true|
      delete_called = true
      table_id_param = table_id
      record_id_param = record_id
      { 'message' => 'Record deleted', 'id' => record_id }
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

    result = client.add_field('tbl_123', field_data, format: :json)

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
      { 'slug' => field_data['slug'], 'label' => field_data['label'] }
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
    mock_response = { 'success' => true }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    fields = [
      { 'slug' => 'field1', 'label' => 'Field 1', 'field_type' => 'textfield', 'is_new' => true },
      { 'slug' => 'field2', 'label' => 'Field 2', 'field_type' => 'numberfield', 'is_new' => true }
    ]

    result = client.bulk_add_fields('tbl_123', fields, format: :json)

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
      { 'success' => true, 'count' => fields.length }
    end

    request = {
      'id' => 12,
      'method' => 'tools/call',
      'params' => {
        'name' => 'bulk_add_fields',
        'arguments' => {
          'table_id' => 'tbl_test',
          'fields' => [
            { 'slug' => 'f1', 'label' => 'Field 1' },
            { 'slug' => 'f2', 'label' => 'Field 2' }
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
    mock_response = { 'slug' => 'test_field', 'label' => 'Updated Label' }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    field_data = { 'label' => 'Updated Label', 'field_type' => 'textfield' }
    result = client.update_field('tbl_123', 'test_field', field_data, format: :json)

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
      { 'slug' => slug, 'label' => field_data['label'] }
    end

    request = {
      'id' => 13,
      'method' => 'tools/call',
      'params' => {
        'name' => 'update_field',
        'arguments' => {
          'table_id' => 'tbl_test',
          'slug' => 'field_slug',
          'field_data' => { 'label' => 'New Label' }
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
    mock_response = { 'slug' => 'deleted_field', 'label' => 'Deleted Field' }

    client.define_singleton_method(:api_request) do |method, endpoint, body = nil|
      api_method = method
      api_endpoint = endpoint
      api_body = body
      mock_response
    end

    result = client.delete_field('tbl_123', 'deleted_field', format: :json)

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
      { 'slug' => slug, 'deleted' => true }
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
        { 'id' => 'rec_1', 'title' => 'Record 1', 'status' => 'approved' },
        { 'id' => 'rec_2', 'title' => 'Record 2', 'status' => 'approved' }
      ],
      'total_records_count' => 2,
      'filter' => { 'operator' => 'and', 'fields' => [] }
    }

    client.define_singleton_method(:api_request) do |method, endpoint, _body = nil|
      api_method = method
      api_endpoint = endpoint
      mock_response
    end

    result = client.get_view_records('tbl_123', 'view_456', format: :json)

    assert_equal :get, api_method, 'Should use GET method'
    assert_equal '/applications/tbl_123/records-for-report/?report=view_456', api_endpoint
    assert_equal 2, result['records'].length
    assert_equal 'rec_1', result['records'][0]['id']
  end

  def test_client_get_view_records_with_empty_values
    client = SmartSuiteClient.new('test_key', 'test_account')

    api_endpoint = nil
    mock_response = { 'records' => [], 'total_records_count' => 0 }

    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      api_endpoint = endpoint
      mock_response
    end

    client.get_view_records('tbl_123', 'view_456', with_empty_values: true, format: :json)

    assert_includes api_endpoint, 'with_empty_values=true', 'Should include with_empty_values parameter'
  end

  def test_handle_tool_call_get_view_records
    client = @server.instance_variable_get(:@client)

    get_view_called = false
    table_id_param = nil
    view_id_param = nil

    client.define_singleton_method(:get_view_records) do |table_id, view_id, with_empty_values: false, format: :toon|
      get_view_called = true
      table_id_param = table_id
      view_id_param = view_id
      {
        'records' => [
          { 'id' => 'rec_1', 'title' => 'Test Record' }
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
      format: :json,
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
    mock_response = { 'id' => 'view_123', 'label' => 'Filtered View' }

    client.define_singleton_method(:api_request) do |_method, _endpoint, body = nil|
      api_body = body
      mock_response
    end

    filter_state = {
      'filterWindow' => {
        'opened' => false,
        'filter' => {
          'operator' => 'and',
          'fields' => [
            { 'field' => 'status', 'comparison' => 'is', 'value' => 'approved' }
          ]
        }
      }
    }

    result = client.create_view(
      'tbl_123',
      'sol_456',
      'Filtered View',
      'grid',
      format: :json,
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
                  { 'field' => 'priority', 'comparison' => 'is', 'value' => 'high' }
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
            'owners' => %w[user_123 user_456]
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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123', format: :json)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123', include_activity_data: true, format: :json)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions_by_owner('user_123', format: :json)

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
    # Use cache_enabled: false to test the fallback API path
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    # Mock responses
    mock_tables_response = {
      'tables' => [
        { 'id' => 'tbl_1', 'name' => 'Table 1' },
        { 'id' => 'tbl_2', 'name' => 'Table 2' }
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

    client.define_singleton_method(:list_tables) do |solution_id: nil, fields: nil, format: :toon|
      mock_tables_response
    end

    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      # Extract table_id from endpoint like "/applications/tbl_1/records/list/?limit=1&offset=0"
      return unless endpoint.include?('/records/list/')

      table_id = endpoint.match(%r{applications/([^/]+)/records})[1]
      mock_records_responses[table_id]
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_equal '2025-01-15T12:00:00Z', result, 'Should return the most recent date across all tables'
  end

  def test_get_solution_most_recent_record_update_returns_nil_when_no_records
    # Use cache_enabled: false to test the fallback API path
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    mock_tables_response = {
      'tables' => [
        { 'id' => 'tbl_1', 'name' => 'Table 1' }
      ],
      'count' => 1
    }

    client.define_singleton_method(:list_tables) do |solution_id: nil, fields: nil, format: :toon|
      mock_tables_response
    end

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      { 'items' => [] }
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_nil result, 'Should return nil when no records exist'
  end

  def test_get_solution_most_recent_record_update_returns_nil_when_no_tables
    # Use cache_enabled: false to test the fallback API path
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    client.define_singleton_method(:list_tables) do |solution_id: nil, fields: nil, format: :toon|
      { 'tables' => [], 'count' => 0 }
    end

    result = client.get_solution_most_recent_record_update('sol_123')

    assert_nil result, 'Should return nil when solution has no tables'
  end

  # Test search_member
  def test_search_member_finds_by_email
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('john.doe', format: :json)

    assert_equal 1, result['count'], 'Should find 1 member by email'
    assert_equal 'john.doe', result['query']
    assert_equal 'user_1', result['members'][0]['id']
    assert_equal 'john.doe@example.com', result['members'][0]['email']
  end

  def test_search_member_finds_by_first_name
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('jane', format: :json)

    assert_equal 1, result['count'], 'Should find 1 member by first name'
    assert_equal 'user_2', result['members'][0]['id']
    assert_equal 'Jane', result['members'][0]['first_name']
  end

  def test_search_member_finds_by_last_name
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('doe', format: :json)

    assert_equal 1, result['count'], 'Should find 1 member by last name'
    assert_equal 'user_1', result['members'][0]['id']
    assert_equal 'Doe', result['members'][0]['last_name']
  end

  def test_search_member_is_case_insensitive
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('JOHN', format: :json)

    assert_equal 1, result['count'], 'Should be case insensitive'
    assert_equal 'user_1', result['members'][0]['id']
  end

  def test_search_member_returns_empty_when_no_matches
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('nonexistent', format: :json)

    assert_equal 0, result['count'], 'Should return 0 when no matches'
    assert_equal 0, result['members'].length
  end

  def test_search_member_handles_email_array
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('john.doe', format: :json)

    assert_equal 1, result['count'], 'Should handle email as array'
    assert_equal 'user_1', result['members'][0]['id']
  end

  def test_search_member_includes_optional_fields
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.search_member('john', format: :json)

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
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions(fields: %w[id name created], format: :json)

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

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      mock_response
    end

    result = client.list_solutions(format: :json)

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
      FileUtils.rm_f(cache_path)
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
      client.define_singleton_method(:get_table) do |table_id, format: :toon|
        api_call_count += 1
        {
          'id' => table_id,
          'name' => 'Test Table',
          'structure' => [
            { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
            { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield' }
          ]
        }
      end

      # Mock fetch_all_records (for cache population)
      client.define_singleton_method(:fetch_all_records) do |_table_id|
        api_call_count += 1
        [
          { 'id' => 'rec_1', 'title' => 'Record 1', 'status' => 'active' },
          { 'id' => 'rec_2', 'title' => 'Record 2', 'status' => 'pending' }
        ]
      end

      # First call should populate cache (2 API calls: get_table + fetch_all_records)
      result1 = client.list_records('tbl_123', 10, 0, fields: %w[title status])
      assert_equal 2, api_call_count, 'Should make 2 API calls to populate cache'

      # Second call should use cache (no additional API calls)
      result2 = client.list_records('tbl_123', 5, 0, fields: ['title'])
      assert_equal 2, api_call_count, 'Should not make additional API calls (cache hit)'

      # Both results should be plain text
      assert result1.is_a?(String), 'Should return plain text'
      assert result2.is_a?(String), 'Should return plain text'
    ensure
      FileUtils.rm_f(cache_path)
    end
  end

  def test_list_records_bypasses_cache_when_disabled
    client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: false)

    api_call_count = 0

    # Mock api_request for direct API calls
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_call_count += 1
      { 'items' => [], 'total_count' => 0 }
    end

    # Each call should hit the API
    client.list_records('tbl_123', 10, 0, fields: ['title'])
    assert_equal 1, api_call_count, 'Should make 1 API call'

    client.list_records('tbl_123', 10, 0, fields: ['title'])
    assert_equal 2, api_call_count, 'Should make another API call (no cache)'
  end

  # Regression test: list_solutions should use cache even when fields parameter is provided
  # Bug fixed: Previously bypassed cache whenever fields parameter was present
  def test_list_solutions_uses_cache_with_fields_parameter
    cache_path = File.join(Dir.tmpdir, "test_cache_#{Time.now.to_i}.db")

    begin
      client = SmartSuiteClient.new('test_key', 'test_account', cache_enabled: true, cache_path: cache_path)

      api_call_count = 0
      mock_response = {
        'items' => [
          {
            'id' => 'sol_1',
            'name' => 'Solution 1',
            'logo_icon' => 'star',
            'logo_color' => '#FF0000',
            'created' => '2025-01-01T00:00:00Z',
            'status' => 'active'
          },
          {
            'id' => 'sol_2',
            'name' => 'Solution 2',
            'logo_icon' => 'rocket',
            'logo_color' => '#00FF00',
            'created' => '2025-01-02T00:00:00Z',
            'status' => 'active'
          }
        ]
      }

      # Mock api_request to track API calls
      client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
        api_call_count += 1
        mock_response
      end

      # First call should populate cache (1 API call)
      result1 = client.list_solutions(format: :json)
      assert_equal 1, api_call_count, 'Should make 1 API call to populate cache'
      assert_equal 2, result1['count'], 'Should return 2 solutions'

      # Second call WITH fields parameter should use cache (no additional API call)
      # This is the regression test - previously this would bypass cache
      result2 = client.list_solutions(fields: %w[id name created], format: :json)
      assert_equal 1, api_call_count, 'Should NOT make additional API call (cache hit)'
      assert_equal 2, result2['count'], 'Should return 2 solutions from cache'

      # Verify client-side filtering worked
      solution = result2['solutions'][0]
      assert_equal 'sol_1', solution['id']
      assert_equal 'Solution 1', solution['name']
      assert_equal '2025-01-01T00:00:00Z', solution['created']
      refute solution.key?('logo_icon'), 'Should not include fields not requested (client-side filtered)'
      refute solution.key?('status'), 'Should not include fields not requested (client-side filtered)'

      # Third call with different fields should still use cache
      result3 = client.list_solutions(fields: %w[id name], format: :json)
      assert_equal 1, api_call_count, 'Should still NOT make additional API call (cache hit)'
      assert_equal 2, result3['count'], 'Should return 2 solutions from cache'

      # Verify different client-side filtering
      solution3 = result3['solutions'][0]
      assert_equal 'sol_1', solution3['id']
      assert_equal 'Solution 1', solution3['name']
      refute solution3.key?('created'), 'Should not include fields not requested'
    ensure
      FileUtils.rm_f(cache_path)
    end
  end

  # ========== Additional tool call handler tests for coverage ==========

  def test_handle_tool_call_analyze_solution_usage
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:analyze_solution_usage) do |days_inactive:, min_records:|
      { 'summary' => { 'total' => 10, 'inactive' => 2 }, 'days_inactive' => days_inactive, 'min_records' => min_records }
    end

    request = {
      'id' => 20,
      'method' => 'tools/call',
      'params' => { 'name' => 'analyze_solution_usage', 'arguments' => { 'days_inactive' => 60, 'min_records' => 5 } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 60, result['days_inactive']
    assert_equal 5, result['min_records']
  end

  def test_handle_tool_call_list_solutions_by_owner
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_solutions_by_owner) do |owner_id, include_activity_data:, format: :toon|
      { 'solutions' => [{ 'id' => 'sol_1', 'owner' => owner_id }], 'count' => 1 }
    end

    request = {
      'id' => 21,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_solutions_by_owner', 'arguments' => { 'owner_id' => 'user_123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'user_123', result['solutions'][0]['owner']
  end

  def test_handle_tool_call_get_solution_most_recent_record_update
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:get_solution_most_recent_record_update) do |solution_id|
      '2025-01-15T12:00:00Z'
    end

    request = {
      'id' => 22,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_solution_most_recent_record_update', 'arguments' => { 'solution_id' => 'sol_123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_includes response['result']['content'][0]['text'], '2025-01-15T12:00:00Z'
  end

  def test_handle_tool_call_search_member
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:search_member) do |query, include_inactive:, format: :toon|
      { 'members' => [{ 'id' => 'mem_1', 'name' => 'John' }], 'count' => 1, 'query' => query }
    end

    request = {
      'id' => 23,
      'method' => 'tools/call',
      'params' => { 'name' => 'search_member', 'arguments' => { 'query' => 'john' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'john', result['query']
  end

  def test_handle_tool_call_list_teams
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_teams) do |format: :toon|
      { 'teams' => [{ 'id' => 'team_1', 'name' => 'Engineering' }], 'count' => 1 }
    end

    request = {
      'id' => 24,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_teams', 'arguments' => {} }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'team_1', result['teams'][0]['id']
  end

  def test_handle_tool_call_get_team
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:get_team) do |team_id|
      { 'id' => team_id, 'name' => 'Engineering', 'members' => [] }
    end

    request = {
      'id' => 25,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_team', 'arguments' => { 'team_id' => 'team_123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'team_123', result['id']
  end

  def test_handle_tool_call_create_table
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:create_table) do |solution_id, name, description:, structure:|
      { 'id' => 'tbl_new', 'name' => name, 'solution' => solution_id }
    end

    request = {
      'id' => 26,
      'method' => 'tools/call',
      'params' => { 'name' => 'create_table', 'arguments' => { 'solution_id' => 'sol_1', 'name' => 'New Table' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'New Table', result['name']
  end

  def test_handle_tool_call_get_record
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:get_record) do |table_id, record_id|
      { 'id' => record_id, 'title' => 'Test Record' }
    end

    request = {
      'id' => 27,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_record', 'arguments' => { 'table_id' => 'tbl_1', 'record_id' => 'rec_1' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 'rec_1', result['id']
  end

  def test_handle_tool_call_create_record
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:create_record) do |table_id, data, minimal_response:|
      { 'id' => 'rec_new', 'success' => true }
    end

    request = {
      'id' => 28,
      'method' => 'tools/call',
      'params' => { 'name' => 'create_record', 'arguments' => { 'table_id' => 'tbl_1', 'data' => { 'title' => 'New' } } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal true, result['success']
  end

  def test_handle_tool_call_update_record
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:update_record) do |table_id, record_id, data, minimal_response:|
      { 'id' => record_id, 'success' => true }
    end

    request = {
      'id' => 29,
      'method' => 'tools/call',
      'params' => { 'name' => 'update_record',
                    'arguments' => { 'table_id' => 'tbl_1', 'record_id' => 'rec_1', 'data' => { 'title' => 'Updated' } } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal true, result['success']
  end

  def test_handle_tool_call_bulk_add_records
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:bulk_add_records) do |table_id, records, minimal_response:|
      { 'created' => records.size, 'success' => true }
    end

    request = {
      'id' => 30,
      'method' => 'tools/call',
      'params' => { 'name' => 'bulk_add_records',
                    'arguments' => { 'table_id' => 'tbl_1', 'records' => [{ 'title' => 'A' }, { 'title' => 'B' }] } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 2, result['created']
  end

  def test_handle_tool_call_bulk_update_records
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:bulk_update_records) do |table_id, records, minimal_response:|
      { 'updated' => records.size, 'success' => true }
    end

    request = {
      'id' => 31,
      'method' => 'tools/call',
      'params' => { 'name' => 'bulk_update_records', 'arguments' => { 'table_id' => 'tbl_1', 'records' => [{ 'id' => 'r1' }] } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal true, result['success']
  end

  def test_handle_tool_call_bulk_delete_records
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:bulk_delete_records) do |table_id, record_ids, minimal_response:|
      { 'deleted' => record_ids.size, 'success' => true }
    end

    request = {
      'id' => 32,
      'method' => 'tools/call',
      'params' => { 'name' => 'bulk_delete_records', 'arguments' => { 'table_id' => 'tbl_1', 'record_ids' => %w[r1 r2] } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 2, result['deleted']
  end

  def test_handle_tool_call_get_file_url
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:get_file_url) do |file_handle|
      { 'url' => "https://files.smartsuite.com/#{file_handle}" }
    end

    request = {
      'id' => 33,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_file_url', 'arguments' => { 'file_handle' => 'abc123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_includes result['url'], 'abc123'
  end

  def test_handle_tool_call_list_deleted_records
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_deleted_records) do |solution_id, preview:, format: :toon|
      { 'deleted_records' => [{ 'id' => 'rec_del' }], 'count' => 1 }
    end

    request = {
      'id' => 34,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_deleted_records', 'arguments' => { 'solution_id' => 'sol_1' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal 1, result['count']
  end

  def test_handle_tool_call_restore_deleted_record
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:restore_deleted_record) do |table_id, record_id|
      { 'restored' => true, 'id' => record_id }
    end

    request = {
      'id' => 35,
      'method' => 'tools/call',
      'params' => { 'name' => 'restore_deleted_record', 'arguments' => { 'table_id' => 'tbl_1', 'record_id' => 'rec_1' } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal true, result['restored']
  end

  def test_handle_tool_call_attach_file
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:attach_file) do |table_id, record_id, file_field_slug, file_urls|
      { 'attached' => file_urls.size, 'success' => true }
    end

    request = {
      'id' => 36,
      'method' => 'tools/call',
      'params' => { 'name' => 'attach_file',
                    'arguments' => { 'table_id' => 'tbl_1', 'record_id' => 'rec_1', 'file_field_slug' => 'attachments', 'file_urls' => ['https://example.com/file.pdf'] } }
    }

    response = call_private_method(:handle_tool_call, request)
    result = JSON.parse(response['result']['content'][0]['text'])
    assert_equal true, result['success']
  end

  def test_handle_tool_call_list_records
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_records) do |table_id, limit, offset, filter:, sort:, fields:, hydrated:, format:|
      "2 of 10 filtered records (100 total)\n\nRecord 1\nRecord 2"
    end

    request = {
      'id' => 37,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_records',
                    'arguments' => { 'table_id' => 'tbl_1', 'limit' => 10, 'offset' => 0, 'fields' => ['title'] } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_includes response['result']['content'][0]['text'], 'Record 1'
  end

  # ==========================================
  # Tests for remaining tool handlers
  # ==========================================

  def test_handle_tool_call_list_comments
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_comments) do |record_id, format: :toon|
      [
        { 'id' => 'comment_1', 'message' => { 'preview' => 'Test comment' }, 'record' => record_id }
      ]
    end

    request = {
      'id' => 38,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_comments', 'arguments' => { 'record_id' => 'rec_123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 38, response['id']
    assert_includes response['result']['content'][0]['text'], 'comment_1'
  end

  def test_handle_tool_call_add_comment
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:add_comment) do |table_id, record_id, message, assigned_to|
      { 'id' => 'comment_new', 'message' => { 'preview' => message }, 'record' => record_id, 'assigned_to' => assigned_to }
    end

    request = {
      'id' => 39,
      'method' => 'tools/call',
      'params' => {
        'name' => 'add_comment',
        'arguments' => {
          'table_id' => 'tbl_123',
          'record_id' => 'rec_123',
          'message' => 'New comment',
          'assigned_to' => 'user_456'
        }
      }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'comment_new'
    assert_includes response['result']['content'][0]['text'], 'New comment'
  end

  def test_handle_tool_call_get_cache_status_when_enabled
    # Cache is enabled by default in setup
    client = @server.instance_variable_get(:@client)
    assert client.cache_enabled?, 'Cache should be enabled for this test'

    cache = client.cache
    cache.define_singleton_method(:get_cache_status) do |table_id:|
      { 'status' => 'valid', 'table_id' => table_id, 'tables_cached' => 5 }
    end

    request = {
      'id' => 40,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_cache_status', 'arguments' => { 'table_id' => 'tbl_123' } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'status'
    assert_includes response['result']['content'][0]['text'], 'valid'
  end

  def test_handle_tool_call_get_cache_status_when_disabled
    # Create a server with cache disabled
    server_no_cache = SmartSuiteServer.new
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    server_no_cache.instance_variable_set(:@client, client)

    request = {
      'id' => 41,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_cache_status', 'arguments' => {} }
    }

    response = server_no_cache.send(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'Cache is disabled'
  end

  def test_handle_tool_call_refresh_cache_when_enabled
    client = @server.instance_variable_get(:@client)
    assert client.cache_enabled?, 'Cache should be enabled for this test'

    cache = client.cache
    cache.define_singleton_method(:refresh_cache) do |resource, table_id:, solution_id:|
      { 'refreshed' => resource, 'table_id' => table_id, 'solution_id' => solution_id }
    end

    request = {
      'id' => 42,
      'method' => 'tools/call',
      'params' => {
        'name' => 'refresh_cache',
        'arguments' => { 'resource' => 'records', 'table_id' => 'tbl_123', 'solution_id' => 'sol_456' }
      }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'refreshed'
    assert_includes response['result']['content'][0]['text'], 'records'
  end

  def test_handle_tool_call_refresh_cache_when_disabled
    server_no_cache = SmartSuiteServer.new
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    server_no_cache.instance_variable_set(:@client, client)

    request = {
      'id' => 43,
      'method' => 'tools/call',
      'params' => { 'name' => 'refresh_cache', 'arguments' => { 'resource' => 'records' } }
    }

    response = server_no_cache.send(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'Cache is disabled'
  end

  def test_handle_tool_call_warm_cache
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:warm_cache) do |tables:, count:|
      { 'status' => 'completed', 'tables' => tables, 'count' => count, 'warmed' => 3 }
    end

    request = {
      'id' => 44,
      'method' => 'tools/call',
      'params' => { 'name' => 'warm_cache', 'arguments' => { 'tables' => %w[tbl_1 tbl_2], 'count' => 10 } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'completed'
    assert_includes response['result']['content'][0]['text'], 'warmed'
  end

  def test_handle_tool_call_error_handling
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_solutions) do |**_args|
      raise StandardError, 'API connection failed'
    end

    request = {
      'id' => 45,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_solutions', 'arguments' => {} }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 45, response['id']
    assert_equal(-32_603, response['error']['code'])
    assert_includes response['error']['message'], 'Tool execution failed'
    assert_includes response['error']['message'], 'API connection failed'
  end

  # ==========================================
  # Tests for send_error method
  # ==========================================

  def test_send_error_outputs_json_rpc_error
    original_stdout = $stdout
    captured_output = StringIO.new
    $stdout = captured_output

    @server.send(:send_error, 'Test error message', 99)

    $stdout = original_stdout
    output = captured_output.string

    response = JSON.parse(output.strip)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 99, response['id']
    assert_equal(-32_603, response['error']['code'])
    assert_equal 'Test error message', response['error']['message']
  end

  # ==========================================
  # Tests for log_metric method
  # ==========================================

  def test_log_metric_writes_to_metrics_log
    metrics_log = @server.instance_variable_get(:@metrics_log)
    # Get the metrics log path
    metrics_path = metrics_log.path

    # Call log_metric
    @server.send(:log_metric, 'Test metric entry')

    # Read the file to verify the entry was written
    content = File.read(metrics_path)
    assert_includes content, 'Test metric entry'
    # Should include a timestamp
    assert_match(/\[\d{2}:\d{2}:\d{2}\]/, content)
  end

  # ==========================================
  # Tests for handle_request routing
  # ==========================================

  def test_handle_request_routes_to_initialize
    request = { 'id' => 50, 'method' => 'initialize', 'params' => {} }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 50, response['id']
    assert response['result']['capabilities']
    assert_equal 'smartsuite-server', response['result']['serverInfo']['name']
  end

  def test_handle_request_routes_to_tools_list
    request = { 'id' => 51, 'method' => 'tools/list', 'params' => {} }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 51, response['id']
    assert response['result']['tools']
  end

  def test_handle_request_routes_to_tools_call
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_teams) do |format: :toon|
      { 'teams' => [{ 'id' => 'team_1' }], 'count' => 1 }
    end

    request = {
      'id' => 52,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_teams', 'arguments' => {} }
    }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 52, response['id']
    assert response['result']['content']
  end

  def test_handle_request_routes_to_prompts_list
    request = { 'id' => 53, 'method' => 'prompts/list', 'params' => {} }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 53, response['id']
    assert response['result']['prompts']
  end

  def test_handle_request_routes_to_prompts_get
    request = { 'id' => 54, 'method' => 'prompts/get', 'params' => { 'name' => 'filter_active_records' } }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 54, response['id']
  end

  def test_handle_request_routes_to_resources_list
    request = { 'id' => 55, 'method' => 'resources/list', 'params' => {} }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 55, response['id']
    assert response['result']['resources']
  end

  def test_handle_request_returns_error_for_unknown_method
    request = { 'id' => 56, 'method' => 'unknown/method', 'params' => {} }
    response = call_private_method(:handle_request, request)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 56, response['id']
    assert_equal(-32_601, response['error']['code'])
    assert_includes response['error']['message'], 'Method not found'
  end

  # ==========================================
  # Tests for list_solutions and list_tables tool handlers
  # ==========================================

  def test_handle_tool_call_list_solutions
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_solutions) do |include_activity_data:, fields:, name:, format:|
      # Return TOON-like string when format is :toon (default), otherwise JSON
      if format == :toon
        "solutions[1]:\n  id, name\n  sol_1, #{name || 'Test'}"
      else
        { 'solutions' => [{ 'id' => 'sol_1', 'name' => name || 'Test' }], 'include_activity' => include_activity_data }
      end
    end

    request = {
      'id' => 57,
      'method' => 'tools/call',
      'params' => {
        'name' => 'list_solutions',
        'arguments' => { 'include_activity_data' => true, 'name' => 'Test' }
      }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'sol_1'
  end

  def test_handle_tool_call_list_tables
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_tables) do |solution_id:, fields:, format: :toon|
      { 'tables' => [{ 'id' => 'tbl_1', 'name' => 'Test Table', 'solution_id' => solution_id }], 'count' => 1 }
    end

    request = {
      'id' => 58,
      'method' => 'tools/call',
      'params' => {
        'name' => 'list_tables',
        'arguments' => { 'solution_id' => 'sol_123', 'fields' => %w[id name] }
      }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'tbl_1'
  end

  def test_handle_tool_call_get_table
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:get_table) do |table_id|
      { 'id' => table_id, 'name' => 'Test Table', 'structure' => [] }
    end

    request = {
      'id' => 59,
      'method' => 'tools/call',
      'params' => { 'name' => 'get_table', 'arguments' => { 'table_id' => 'tbl_456' } }
    }

    response = call_private_method(:handle_tool_call, request)
    assert_equal '2.0', response['jsonrpc']
    assert_includes response['result']['content'][0]['text'], 'tbl_456'
  end

  # ==========================================
  # Tests for run method (main loop)
  # ==========================================

  def test_run_processes_valid_request
    # Create input that will be read from stdin
    request = { 'jsonrpc' => '2.0', 'id' => 100, 'method' => 'initialize', 'params' => {} }
    input = StringIO.new("#{JSON.generate(request)}\n")
    output = StringIO.new

    # Save original stdin/stdout
    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new # Suppress stderr warnings

      # Run server - it will process one request and exit when stdin is empty
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    # Parse the output
    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 100, response['id']
    assert response['result']['capabilities']
  end

  def test_run_handles_notification_without_response
    # Notifications have no 'id' field and should not get a response
    notification = { 'jsonrpc' => '2.0', 'method' => 'notifications/initialized', 'params' => {} }
    input = StringIO.new("#{JSON.generate(notification)}\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    # Output should be empty for notifications
    assert_empty output.string.strip, 'Notifications should not receive responses'
  end

  def test_run_handles_json_parse_error
    input = StringIO.new("not valid json\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    assert_equal(-32_700, response['error']['code'])
    assert_includes response['error']['message'], 'Parse error'
  end

  def test_run_handles_empty_input_lines
    # Empty lines should be skipped
    request = { 'jsonrpc' => '2.0', 'id' => 101, 'method' => 'initialize', 'params' => {} }
    input = StringIO.new("\n\n#{JSON.generate(request)}\n\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 101, response['id']
  end

  def test_run_logs_tool_calls
    # Set up client mock
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_teams) do |format: :toon|
      { 'teams' => [{ 'id' => 'team_1' }], 'count' => 1 }
    end

    request = {
      'jsonrpc' => '2.0',
      'id' => 102,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_teams', 'arguments' => {} }
    }
    input = StringIO.new("#{JSON.generate(request)}\n")
    output = StringIO.new
    stderr_output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = stderr_output
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    assert_equal 102, response['id']
    assert response['result']['content']
  end

  def test_run_handles_multiple_requests
    request1 = { 'jsonrpc' => '2.0', 'id' => 103, 'method' => 'initialize', 'params' => {} }
    request2 = { 'jsonrpc' => '2.0', 'id' => 104, 'method' => 'resources/list', 'params' => {} }
    input = StringIO.new("#{JSON.generate(request1)}\n#{JSON.generate(request2)}\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    # Parse both responses
    lines = output.string.strip.split("\n")
    assert_equal 2, lines.length

    response1 = JSON.parse(lines[0])
    response2 = JSON.parse(lines[1])

    assert_equal 103, response1['id']
    assert_equal 104, response2['id']
  end

  def test_run_handles_standard_error
    # Create a client that raises StandardError
    client = @server.instance_variable_get(:@client)
    client.define_singleton_method(:list_solutions) do |**_args|
      raise StandardError, 'Unexpected error'
    end

    request = {
      'jsonrpc' => '2.0',
      'id' => 105,
      'method' => 'tools/call',
      'params' => { 'name' => 'list_solutions', 'arguments' => {} }
    }
    input = StringIO.new("#{JSON.generate(request)}\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    # The error should be caught at the tool call level, returning a valid response
    assert_equal 105, response['id']
    assert_equal(-32_603, response['error']['code'])
  end

  def test_run_handles_error_in_handle_request
    # Override handle_request to raise an error directly
    @server.define_singleton_method(:handle_request) do |_request|
      raise StandardError, 'Error in handle_request'
    end

    request = { 'jsonrpc' => '2.0', 'id' => 106, 'method' => 'initialize', 'params' => {} }
    input = StringIO.new("#{JSON.generate(request)}\n")
    output = StringIO.new

    original_stdin = $stdin
    original_stdout = $stdout
    original_stderr = $stderr

    begin
      $stdin = input
      $stdout = output
      $stderr = StringIO.new
      @server.run
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
      $stderr = original_stderr
    end

    response = JSON.parse(output.string.strip)
    assert_equal '2.0', response['jsonrpc']
    # ID should be nil since we couldn't determine it in the outer catch
    assert_nil response['id']
    assert_equal(-32_603, response['error']['code'])
    assert_includes response['error']['message'], 'Internal error'
  end
end
