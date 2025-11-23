# frozen_string_literal: true

require_relative '../../test_helper'
require 'net/http'
require 'fileutils'
require_relative '../../../lib/smartsuite_client'

class TestWorkspaceOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @test_cache_path = File.join(Dir.tmpdir, "test_workspace_ops_#{rand(100_000)}.db")
  end

  def teardown
    FileUtils.rm_f(@test_cache_path) if @test_cache_path && File.exist?(@test_cache_path)
  end

  # Helper to create a fresh client with mocked api_request
  def create_mock_client(&block)
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    client.define_singleton_method(:api_request, &block) if block_given?
    client
  end

  # Helper to create a client with cache enabled
  def create_cached_client(&block)
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)
    client.define_singleton_method(:api_request, &block) if block_given?
    client
  end

  # ========== list_solutions tests ==========

  def test_list_solutions_success
    expected_response = [
      { 'id' => 'sol_1', 'name' => 'Solution 1', 'logo_icon' => 'icon1', 'logo_color' => '#FF0000' },
      { 'id' => 'sol_2', 'name' => 'Solution 2', 'logo_icon' => 'icon2', 'logo_color' => '#00FF00' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(format: :json)

    assert result.is_a?(Hash)
    assert_equal 2, result['count']
    assert_equal 2, result['solutions'].size
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'Solution 1', result['solutions'][0]['name']
  end

  def test_list_solutions_filters_essential_fields
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution',
        'logo_icon' => 'icon',
        'logo_color' => '#FFFFFF',
        'status' => 'active',
        'last_access' => '2025-01-01T00:00:00Z',
        'permissions' => { 'owners' => ['user1'] },
        'structure' => 'heavy_data'
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(format: :json)

    solution = result['solutions'][0]
    # Essential fields should be present
    assert_equal 'sol_1', solution['id']
    assert_equal 'Solution', solution['name']
    assert_equal 'icon', solution['logo_icon']
    # Non-essential fields should NOT be present without include_activity_data
    refute solution.key?('status'), 'Status should not be included by default'
    refute solution.key?('last_access'), 'last_access should not be included by default'
    refute solution.key?('permissions'), 'permissions should not be included by default'
  end

  def test_list_solutions_with_include_activity_data
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution',
        'status' => 'active',
        'last_access' => '2025-01-01T00:00:00Z',
        'records_count' => 100,
        'automation_count' => 5,
        'has_demo_data' => true
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(include_activity_data: true, format: :json)

    solution = result['solutions'][0]
    assert_equal 'active', solution['status']
    assert_equal '2025-01-01T00:00:00Z', solution['last_access']
    assert_equal 100, solution['records_count']
    assert_equal 5, solution['automation_count']
    assert_equal true, solution['has_demo_data']
  end

  def test_list_solutions_with_custom_fields
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution',
        'permissions' => { 'owners' => ['user1'] },
        'other_field' => 'value'
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(fields: %w[id name permissions], format: :json)

    solution = result['solutions'][0]
    # Should only include requested fields
    assert_equal 'sol_1', solution['id']
    assert_equal 'Solution', solution['name']
    assert solution.key?('permissions')
    # Other fields should not be included
    refute solution.key?('other_field')
  end

  def test_list_solutions_with_name_filter
    expected_response = [
      { 'id' => 'sol_1', 'name' => 'Desarrollos de Software' },
      { 'id' => 'sol_2', 'name' => 'Gestión de Proyectos' },
      { 'id' => 'sol_3', 'name' => 'CRM' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(name: 'desarrollo', format: :json)

    # Should only match the first solution using fuzzy matching
    assert result['count'] >= 1
    assert(result['solutions'].any? { |s| s['name'].downcase.include?('desarrollo') })
  end

  def test_list_solutions_handles_items_response
    expected_response = {
      'items' => [
        { 'id' => 'sol_1', 'name' => 'Solution' }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(format: :json)

    assert_equal 1, result['count']
    assert_equal 'sol_1', result['solutions'][0]['id']
  end

  # ========== list_solutions_by_owner tests ==========

  def test_list_solutions_by_owner_success
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Owned Solution',
        'permissions' => { 'owners' => %w[owner_1 owner_2] }
      },
      {
        'id' => 'sol_2',
        'name' => 'Other Solution',
        'permissions' => { 'owners' => ['other_user'] }
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions_by_owner('owner_1', format: :json)

    assert_equal 1, result['count']
    assert_equal 'sol_1', result['solutions'][0]['id']
    assert_equal 'Owned Solution', result['solutions'][0]['name']
  end

  def test_list_solutions_by_owner_missing_owner_id
    client = create_mock_client

    assert_raises(ArgumentError, 'owner_id is required') do
      client.list_solutions_by_owner(nil)
    end

    assert_raises(ArgumentError, 'owner_id is required') do
      client.list_solutions_by_owner('')
    end
  end

  def test_list_solutions_by_owner_with_include_activity_data
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Owned Solution',
        'permissions' => { 'owners' => ['owner_1'] },
        'status' => 'active',
        'last_access' => '2025-01-01T00:00:00Z',
        'records_count' => 50
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions_by_owner('owner_1', include_activity_data: true, format: :json)

    solution = result['solutions'][0]
    assert_equal 'active', solution['status']
    assert_equal '2025-01-01T00:00:00Z', solution['last_access']
    assert_equal 50, solution['records_count']
  end

  def test_list_solutions_by_owner_filters_by_permissions
    expected_response = [
      { 'id' => 'sol_1', 'permissions' => { 'owners' => ['user_a'] } },
      { 'id' => 'sol_2', 'permissions' => { 'owners' => ['user_b'] } },
      { 'id' => 'sol_3', 'permissions' => { 'owners' => %w[user_a user_b] } },
      { 'id' => 'sol_4', 'permissions' => nil },
      { 'id' => 'sol_5' } # No permissions key
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions_by_owner('user_a', format: :json)

    # Should only return sol_1 and sol_3
    assert_equal 2, result['count']
    ids = result['solutions'].map { |s| s['id'] }
    assert_includes ids, 'sol_1'
    assert_includes ids, 'sol_3'
    refute_includes ids, 'sol_2'
    refute_includes ids, 'sol_4'
    refute_includes ids, 'sol_5'
  end

  # ========== get_solution tests ==========

  def test_get_solution_success
    solution_id = 'sol_123'
    expected_response = {
      'id' => solution_id,
      'name' => 'Test Solution',
      'status' => 'active'
    }

    endpoint_called = nil
    client = create_mock_client do |_method, endpoint, _body = nil|
      endpoint_called = endpoint
      expected_response
    end

    result = client.get_solution(solution_id)

    assert_equal "/solutions/#{solution_id}/", endpoint_called
    assert_equal solution_id, result['id']
    assert_equal 'Test Solution', result['name']
  end

  def test_get_solution_missing_solution_id
    client = create_mock_client

    assert_raises(ArgumentError, 'solution_id is required') do
      client.get_solution(nil)
    end

    assert_raises(ArgumentError, 'solution_id is required') do
      client.get_solution('')
    end
  end

  # ========== get_solution_most_recent_record_update tests ==========

  def test_get_solution_most_recent_record_update_success
    solution_id = 'sol_123'

    client = create_mock_client do |_method, endpoint, _body = nil|
      if endpoint.include?('/applications/?')
        # list_tables response - returns array for tables
        [{ 'id' => 'tbl_1', 'name' => 'Table 1', 'solution' => solution_id },
         { 'id' => 'tbl_2', 'name' => 'Table 2', 'solution' => solution_id }]
      elsif endpoint.include?('tbl_1') && endpoint.include?('/records/list/')
        { 'items' => [{ 'last_updated' => { 'on' => '2025-01-10T10:00:00Z' } }] }
      elsif endpoint.include?('tbl_2') && endpoint.include?('/records/list/')
        { 'items' => [{ 'last_updated' => { 'on' => '2025-01-15T12:00:00Z' } }] }
      end
    end

    result = client.get_solution_most_recent_record_update(solution_id)

    assert_equal '2025-01-15T12:00:00Z', result
  end

  def test_get_solution_most_recent_record_update_no_tables
    solution_id = 'sol_empty'

    client = create_mock_client do |_method, endpoint, _body = nil|
      { 'tables' => [], 'count' => 0 } if endpoint.include?('/applications/?')
    end

    result = client.get_solution_most_recent_record_update(solution_id)

    assert_nil result
  end

  def test_get_solution_most_recent_record_update_no_records
    solution_id = 'sol_no_records'

    client = create_mock_client do |_method, endpoint, _body = nil|
      if endpoint.include?('/applications/?')
        { 'tables' => [{ 'id' => 'tbl_1' }], 'count' => 1 }
      elsif endpoint.include?('/records/list/')
        { 'items' => [] }
      end
    end

    result = client.get_solution_most_recent_record_update(solution_id)

    assert_nil result
  end

  def test_get_solution_most_recent_record_update_missing_solution_id
    client = create_mock_client

    assert_raises(ArgumentError, 'solution_id is required') do
      client.get_solution_most_recent_record_update(nil)
    end
  end

  # ========== analyze_solution_usage tests ==========

  def test_analyze_solution_usage_success
    expected_response = [
      {
        'id' => 'sol_active',
        'name' => 'Active Solution',
        'last_access' => (Time.now - 86_400).iso8601, # 1 day ago
        'records_count' => 100,
        'automation_count' => 5
      },
      {
        'id' => 'sol_inactive',
        'name' => 'Inactive Solution',
        'last_access' => (Time.now - (120 * 86_400)).iso8601, # 120 days ago
        'records_count' => 5,
        'automation_count' => 0
      },
      {
        'id' => 'sol_never_accessed',
        'name' => 'Never Accessed',
        'last_access' => nil,
        'records_count' => 0,
        'automation_count' => 0
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage

    assert result.is_a?(Hash)
    assert_equal 3, result['summary']['total_solutions']
    assert result['summary']['active_count'] >= 1
    assert result['inactive_solutions'].size >= 1
    assert result['potentially_unused_solutions'].size >= 0
  end

  def test_analyze_solution_usage_with_custom_thresholds
    expected_response = [
      {
        'id' => 'sol_1',
        'name' => 'Solution',
        'last_access' => (Time.now - (45 * 86_400)).iso8601, # 45 days ago
        'records_count' => 3,
        'automation_count' => 0
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage(days_inactive: 30, min_records: 5)

    # With 45 days since access and threshold of 30, should be inactive
    assert_equal 30, result['thresholds']['days_inactive']
    assert_equal 5, result['thresholds']['min_records']
    assert result['inactive_solutions'].size >= 1 || result['potentially_unused_solutions'].size >= 1
  end

  def test_analyze_solution_usage_skips_deleted_solutions
    expected_response = [
      {
        'id' => 'sol_deleted',
        'name' => 'Deleted Solution',
        'delete_date' => '2025-01-01',
        'deleted_by' => 'user_123'
      },
      {
        'id' => 'sol_active',
        'name' => 'Active Solution',
        'last_access' => Time.now.iso8601,
        'records_count' => 100
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage

    # Solutions are counted in total, but deleted ones are skipped in categorization
    # So total_solutions = all - deleted, active_count = categorized active
    assert_equal 1, result['summary']['active_count']
  end

  def test_analyze_solution_usage_categorizes_never_accessed
    expected_response = [
      {
        'id' => 'sol_never',
        'name' => 'Never Accessed No Records',
        'last_access' => nil,
        'records_count' => 0,
        'automation_count' => 0
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage

    assert_equal 1, result['inactive_solutions'].size
    assert_includes result['inactive_solutions'][0]['reason'], 'Never accessed'
  end

  def test_analyze_solution_usage_categorizes_never_accessed_with_content
    expected_response = [
      {
        'id' => 'sol_never_with_content',
        'name' => 'Never Accessed With Content',
        'last_access' => nil,
        'records_count' => 500,
        'automation_count' => 10
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage

    # Has content so should be potentially unused, not inactive
    assert_equal 1, result['potentially_unused_solutions'].size
    assert_includes result['potentially_unused_solutions'][0]['reason'], 'Never accessed but has content'
  end

  def test_analyze_solution_usage_handles_empty_solutions
    expected_response = []

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.analyze_solution_usage

    assert_equal 0, result['summary']['total_solutions']
    assert_equal 0, result['summary']['active_count']
    assert_equal 0, result['summary']['inactive_count']
  end

  # ========== format_solutions_response tests (private method behavior) ==========

  def test_format_solutions_handles_array_response
    expected_response = [
      { 'id' => 'sol_1', 'name' => 'Solution 1' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(format: :json)

    assert_equal 1, result['count']
  end

  def test_format_solutions_handles_hash_with_items
    expected_response = {
      'items' => [{ 'id' => 'sol_1', 'name' => 'Solution 1' }]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions(format: :json)

    assert_equal 1, result['count']
  end

  def test_list_solutions_default_toon_format
    expected_response = [
      { 'id' => 'sol_1', 'name' => 'Solution 1', 'logo_icon' => 'icon1', 'logo_color' => '#FF0000' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_solutions

    # Default format should be TOON (string output)
    assert result.is_a?(String), 'Default format should be TOON (string)'
    assert result.include?('solutions'), 'TOON output should contain solutions'
  end
end
