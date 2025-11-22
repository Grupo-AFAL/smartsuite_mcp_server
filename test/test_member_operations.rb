# frozen_string_literal: true

require_relative 'test_helper'
require 'net/http'
require 'fileutils'
require_relative '../lib/smartsuite_client'

class TestMemberOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @test_cache_path = File.join(Dir.tmpdir, "test_member_ops_#{rand(100_000)}.db")
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

  # ========== list_members tests ==========

  def test_list_members_success
    expected_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => 'user1@test.com', 'role' => '3', 'status' => { 'value' => '1' },
          'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' } },
        { 'id' => 'mem_2', 'email' => ['user2@test.com'], 'role' => '3', 'status' => '1',
          'full_name' => { 'first_name' => 'Jane', 'last_name' => 'Smith', 'sys_root' => 'Jane Smith' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_members

    assert result.is_a?(Hash)
    assert_equal 2, result['count']
    assert_equal 2, result['members'].size
    assert_equal 'mem_1', result['members'][0]['id']
  end

  def test_list_members_extracts_email_from_array
    expected_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => ['array@test.com'], 'full_name' => { 'sys_root' => 'Test User' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_members

    assert_equal 'array@test.com', result['members'][0]['email']
  end

  def test_list_members_extracts_status_from_hash
    expected_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => 'test@test.com',
          'status' => { 'value' => 'active', 'updated_on' => '2025-01-01T00:00:00Z' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_members

    assert_equal 'active', result['members'][0]['status']
  end

  def test_list_members_with_include_inactive
    expected_response = {
      'items' => [
        { 'id' => 'mem_active', 'email' => 'active@test.com', 'deleted_date' => nil },
        { 'id' => 'mem_deleted', 'email' => 'deleted@test.com', 'deleted_date' => { 'date' => '2025-01-01' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }

    # Without include_inactive - should filter out deleted members
    result_active = client.list_members(include_inactive: false)
    assert_equal 1, result_active['count']
    assert_equal 'mem_active', result_active['members'][0]['id']

    # With include_inactive - should include all
    result_all = client.list_members(include_inactive: true)
    assert_equal 2, result_all['count']
  end

  # ========== search_member tests ==========

  def test_search_member_success
    expected_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => 'john@test.com',
          'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' } },
        { 'id' => 'mem_2', 'email' => 'jane@test.com',
          'full_name' => { 'first_name' => 'Jane', 'last_name' => 'Doe', 'sys_root' => 'Jane Doe' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.search_member('Doe')

    assert result.is_a?(Hash)
    assert_equal 2, result['count']
    assert_equal 'Doe', result['query']
  end

  def test_search_member_missing_query
    client = create_mock_client

    assert_raises(ArgumentError, 'query is required') do
      client.search_member(nil)
    end

    assert_raises(ArgumentError, 'query is required') do
      client.search_member('')
    end
  end

  def test_search_member_filters_by_query
    expected_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => 'john@test.com',
          'full_name' => { 'first_name' => 'John', 'last_name' => 'Smith', 'sys_root' => 'John Smith' } },
        { 'id' => 'mem_2', 'email' => 'jane@test.com',
          'full_name' => { 'first_name' => 'Jane', 'last_name' => 'Doe', 'sys_root' => 'Jane Doe' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.search_member('John')

    # Fuzzy matching - should find John
    assert result['members'].any? { |m| m['first_name'] == 'John' }
  end

  def test_search_member_sorts_by_match_score
    expected_response = {
      'items' => [
        { 'id' => 'mem_fuzzy', 'email' => 'fuzzy@test.com',
          'full_name' => { 'first_name' => 'Tania', 'last_name' => 'Test', 'sys_root' => 'Tania Test' } },
        { 'id' => 'mem_exact', 'email' => 'exact@test.com',
          'full_name' => { 'first_name' => 'Vania', 'last_name' => 'Test', 'sys_root' => 'Vania Test' } }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.search_member('Vania')

    # Vania should come first (exact match)
    assert_equal 'Vania', result['members'][0]['first_name']
  end

  # ========== list_teams tests ==========

  def test_list_teams_success
    expected_response = [
      { 'id' => 'team_1', 'name' => 'Team A', 'description' => 'Desc A', 'members' => %w[m1 m2] },
      { 'id' => 'team_2', 'name' => 'Team B', 'description' => nil, 'members' => ['m3'] }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_teams

    assert result.is_a?(Array)
    assert_equal 2, result.size
    assert_equal 'team_1', result[0]['id']
    assert_equal 'Team A', result[0]['name']
    assert_equal 2, result[0]['member_count']
  end

  def test_list_teams_returns_member_count_not_ids
    expected_response = [
      { 'id' => 'team_1', 'name' => 'Team', 'members' => %w[m1 m2 m3 m4 m5] }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_teams

    team = result[0]
    assert_equal 5, team['member_count']
    refute team.key?('members'), 'Should not include member IDs array'
  end

  def test_list_teams_handles_items_response
    expected_response = {
      'items' => [
        { 'id' => 'team_1', 'name' => 'Team', 'members' => ['m1'] }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_teams

    assert_equal 1, result.size
    assert_equal 'team_1', result[0]['id']
  end

  # ========== get_team tests ==========

  def test_get_team_success
    teams_response = [
      { 'id' => 'team_123', 'name' => 'Engineering', 'description' => 'Dev team',
        'members' => %w[mem_1 mem_2] }
    ]

    members_response = {
      'items' => [
        { 'id' => 'mem_1', 'email' => 'dev1@test.com',
          'full_name' => { 'first_name' => 'Dev', 'last_name' => 'One', 'sys_root' => 'Dev One' } },
        { 'id' => 'mem_2', 'email' => 'dev2@test.com',
          'full_name' => { 'first_name' => 'Dev', 'last_name' => 'Two', 'sys_root' => 'Dev Two' } }
      ]
    }

    client = create_cached_client do |_method, endpoint, _body = nil|
      if endpoint.include?('/teams/')
        teams_response
      else
        members_response
      end
    end

    result = client.get_team('team_123')

    assert result.is_a?(Hash)
    assert_equal 'team_123', result['id']
    assert_equal 'Engineering', result['name']
    assert_equal 2, result['member_count']
    assert result['members'].is_a?(Array)
    assert_equal 2, result['members'].size
    # Each member should at least have an 'id' key
    assert result['members'].all? { |m| m.key?('id') }
  end

  def test_get_team_missing_team_id
    client = create_mock_client

    assert_raises(ArgumentError, 'team_id is required') do
      client.get_team(nil)
    end

    assert_raises(ArgumentError, 'team_id is required') do
      client.get_team('')
    end
  end

  def test_get_team_not_found
    expected_response = []

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.get_team('nonexistent')

    assert_nil result
  end

  # ========== format_member_list tests ==========

  def test_format_member_list_extracts_fields
    client = create_mock_client
    items = [
      {
        'id' => 'mem_1',
        'email' => 'user@test.com',
        'role' => '3',
        'status' => { 'value' => '1' },
        'full_name' => { 'first_name' => 'First', 'last_name' => 'Last', 'sys_root' => 'First Last' },
        'job_title' => 'Developer',
        'department' => 'Engineering'
      }
    ]

    result = client.send(:format_member_list, items)

    member = result[0]
    assert_equal 'mem_1', member['id']
    assert_equal 'user@test.com', member['email']
    assert_equal '3', member['role']
    assert_equal '1', member['status']
    assert_equal 'First', member['first_name']
    assert_equal 'Last', member['last_name']
    assert_equal 'First Last', member['full_name']
    assert_equal 'Developer', member['job_title']
    assert_equal 'Engineering', member['department']
  end

  def test_format_member_list_handles_deleted_date
    client = create_mock_client
    items = [
      { 'id' => 'mem_1', 'email' => 'test@test.com', 'deleted_date' => { 'date' => '2025-01-01T00:00:00Z' } }
    ]

    result = client.send(:format_member_list, items)

    assert_equal '2025-01-01T00:00:00Z', result[0]['deleted_date']
  end

  # ========== member_active? tests ==========

  def test_member_active_returns_true_for_nil_deleted_date
    client = create_mock_client
    member = { 'id' => 'mem_1', 'deleted_date' => nil }

    assert client.send(:member_active?, member)
  end

  def test_member_active_returns_true_for_empty_deleted_date
    client = create_mock_client
    member = { 'id' => 'mem_1', 'deleted_date' => '' }

    assert client.send(:member_active?, member)
  end

  def test_member_active_returns_false_for_deleted_member
    client = create_mock_client
    member = { 'id' => 'mem_1', 'deleted_date' => '2025-01-01' }

    refute client.send(:member_active?, member)
  end

  # ========== match_member_formatted? tests ==========

  def test_match_member_formatted_matches_email
    client = create_mock_client
    member = { 'email' => 'john@example.com', 'first_name' => 'John', 'full_name' => 'John Doe' }

    assert client.send(:match_member_formatted?, member, 'example.com')
  end

  def test_match_member_formatted_uses_fuzzy_matching
    client = create_mock_client
    member = { 'email' => 'vania@test.com', 'first_name' => 'Vania', 'full_name' => 'Vania Torres' }

    # Fuzzy match - tania is similar to vania
    assert client.send(:match_member_formatted?, member, 'tania')
  end

  def test_match_member_formatted_matches_full_name
    client = create_mock_client
    member = { 'email' => 'test@test.com', 'first_name' => 'John', 'full_name' => 'John Doe' }

    assert client.send(:match_member_formatted?, member, 'Doe')
  end

  # ========== sort_members_by_match_score tests ==========

  def test_sort_members_by_match_score_exact_first
    client = create_mock_client
    members = [
      { 'full_name' => 'Tania Test', 'first_name' => 'Tania', 'last_name' => 'Test' },
      { 'full_name' => 'Vania Torres', 'first_name' => 'Vania', 'last_name' => 'Torres' }
    ]

    result = client.send(:sort_members_by_match_score, members, 'Vania')

    assert_equal 'Vania', result[0]['first_name']
    assert_equal 'Tania', result[1]['first_name']
  end

  # ========== format_team_list tests ==========

  def test_format_team_list_replaces_members_with_count
    client = create_mock_client
    teams = [
      { 'id' => 'team_1', 'name' => 'Team A', 'description' => 'Desc', 'members' => %w[m1 m2 m3] }
    ]

    result = client.send(:format_team_list, teams)

    assert_equal 3, result[0]['member_count']
    refute result[0].key?('members')
  end

  def test_format_team_list_handles_nil_members
    client = create_mock_client
    teams = [
      { 'id' => 'team_1', 'name' => 'Team A', 'members' => nil }
    ]

    result = client.send(:format_team_list, teams)

    assert_equal 0, result[0]['member_count']
  end

  def test_format_team_list_handles_non_array
    client = create_mock_client

    result = client.send(:format_team_list, 'not an array')

    assert_equal 'not an array', result
  end

  # ========== Cache hit tests ==========

  # Helper to create formatted member data (as it would be after format_member_list)
  def formatted_member(id:, email:, first_name:, last_name:, role: '3', deleted_date: nil)
    {
      'id' => id,
      'email' => email,
      'role' => role,
      'first_name' => first_name,
      'last_name' => last_name,
      'full_name' => "#{first_name} #{last_name}",
      'deleted_date' => deleted_date
    }
  end

  def test_list_members_uses_cache_when_available
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache with formatted members
    cached_members = [
      formatted_member(id: 'mem_cached_1', email: 'cached1@test.com', first_name: 'Cached', last_name: 'User1'),
      formatted_member(id: 'mem_cached_2', email: 'cached2@test.com', first_name: 'Cached', last_name: 'User2')
    ]
    client.cache.cache_members(cached_members)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.list_members

    refute api_called, 'Should use cache when members are cached'
    assert_equal 2, result['count']
  end

  def test_search_member_uses_cache_when_available
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache with formatted members
    cached_members = [
      formatted_member(id: 'mem_search_1', email: 'john@test.com', first_name: 'John', last_name: 'Doe'),
      formatted_member(id: 'mem_search_2', email: 'jane@test.com', first_name: 'Jane', last_name: 'Smith')
    ]
    client.cache.cache_members(cached_members)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.search_member('john')

    refute api_called, 'Should use cache when searching members'
    assert_equal 1, result['count']
    assert_equal 'mem_search_1', result['members'][0]['id']
  end

  def test_search_member_cache_miss_path
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Don't pre-populate cache - cache miss
    api_response = {
      'items' => [
        { 'id' => 'mem_api_1', 'email' => 'john@test.com', 'role' => '3',
          'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' } }
      ]
    }

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_response
    end

    result = client.search_member('john')

    assert_equal 1, result['count']
  end

  def test_list_members_with_empty_solution_members
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)
    solution_id = 'sol_empty_members'

    # Mock solution response with empty members
    solution_response = {
      'id' => solution_id,
      'permissions' => { 'members' => [] }
    }

    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      if endpoint.include?('solutions')
        solution_response
      else
        raise "Unexpected API call"
      end
    end

    result = client.list_members(solution_id: solution_id)

    assert_equal 0, result['count']
    assert_equal [], result['members']
  end

  def test_list_members_with_include_inactive_uses_cache
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache with formatted members including deleted
    cached_members = [
      formatted_member(id: 'mem_active', email: 'active@test.com', first_name: 'Active', last_name: 'User'),
      formatted_member(id: 'mem_deleted', email: 'deleted@test.com', first_name: 'Deleted', last_name: 'User',
                       deleted_date: '2024-01-01T00:00:00Z')
    ]
    client.cache.cache_members(cached_members)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.list_members(include_inactive: true)

    refute api_called, 'Should use cache'
    assert_equal 2, result['count'], 'Should include inactive when flag is true'
  end

  def test_list_members_cache_miss_fetches_from_api
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Don't pre-populate cache - will cause miss
    api_response = {
      'items' => [
        { 'id' => 'mem_api', 'email' => 'api@test.com', 'role' => '3',
          'full_name' => { 'first_name' => 'API', 'last_name' => 'User', 'sys_root' => 'API User' } }
      ]
    }

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_response
    end

    result = client.list_members

    assert_equal 1, result['count']
    assert_equal 'mem_api', result['members'][0]['id']
  end

  # ========== match_member? tests (raw API format) ==========

  def test_match_member_matches_email
    client = create_mock_client
    member = {
      'email' => 'john@example.com',
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    assert client.send(:match_member?, member, 'john@example')
    assert client.send(:match_member?, member, 'example.com')
  end

  def test_match_member_matches_email_array
    client = create_mock_client
    member = {
      'email' => ['john@example.com', 'john.doe@work.com'],
      'full_name' => nil
    }

    # Should match first email
    assert client.send(:match_member?, member, 'john@example')
  end

  def test_match_member_matches_first_name
    client = create_mock_client
    member = {
      'email' => 'test@test.com',
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    assert client.send(:match_member?, member, 'john')
  end

  def test_match_member_matches_last_name
    client = create_mock_client
    member = {
      'email' => 'test@test.com',
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    assert client.send(:match_member?, member, 'doe')
  end

  def test_match_member_matches_full_name
    client = create_mock_client
    member = {
      'email' => 'test@test.com',
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    assert client.send(:match_member?, member, 'john doe')
  end

  def test_match_member_no_match
    client = create_mock_client
    member = {
      'email' => 'test@test.com',
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    refute client.send(:match_member?, member, 'xyz123')
  end

  def test_match_member_nil_email
    client = create_mock_client
    member = {
      'email' => nil,
      'full_name' => { 'first_name' => 'John', 'last_name' => 'Doe', 'sys_root' => 'John Doe' }
    }

    # Should still match on name
    assert client.send(:match_member?, member, 'john')
  end

  def test_match_member_nil_full_name
    client = create_mock_client
    member = {
      'email' => 'test@test.com',
      'full_name' => nil
    }

    # Should still match on email
    assert client.send(:match_member?, member, 'test@test')
    refute client.send(:match_member?, member, 'john')
  end

  # ========== enrich_team_with_members tests ==========

  def test_enrich_team_with_members_handles_nil_members
    client = create_cached_client
    team = { 'id' => 'team_1', 'name' => 'Team', 'members' => nil }

    result = client.send(:enrich_team_with_members, team)

    assert_equal team, result, 'Should return original team when members is nil'
  end

  def test_enrich_team_with_members_enriches_found_members
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate member cache
    cached_members = [
      formatted_member(id: 'mem_1', email: 'dev1@test.com', first_name: 'Dev', last_name: 'One')
    ]
    client.cache.cache_members(cached_members)

    team = {
      'id' => 'team_1',
      'name' => 'Engineering',
      'description' => 'Dev team',
      'members' => ['mem_1', 'mem_2']
    }

    result = client.send(:enrich_team_with_members, team)

    assert_equal 'team_1', result['id']
    assert_equal 'Engineering', result['name']
    assert_equal 2, result['member_count']
    assert_equal 2, result['members'].size

    # First member should be enriched
    assert_equal 'mem_1', result['members'][0]['id']
    assert_equal 'dev1@test.com', result['members'][0]['email']

    # Second member not in cache - should just have id
    assert_equal 'mem_2', result['members'][1]['id']
    refute result['members'][1].key?('email')
  end

  # ========== list_members by solution edge cases ==========

  def test_list_members_by_solution_with_team_members
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    solution_response = {
      'id' => 'sol_123',
      'permissions' => {
        'members' => [{ 'entity' => 'mem_direct', 'access' => 'full' }],
        'owners' => ['mem_owner'],
        'teams' => [{ 'entity' => 'team_1', 'access' => 'full' }]
      }
    }

    team_response = [
      { 'id' => 'team_1', 'name' => 'Dev Team', 'members' => %w[mem_team_1 mem_team_2] }
    ]

    members_response = {
      'items' => [
        { 'id' => 'mem_direct', 'email' => 'direct@test.com',
          'full_name' => { 'sys_root' => 'Direct User' } },
        { 'id' => 'mem_owner', 'email' => 'owner@test.com',
          'full_name' => { 'sys_root' => 'Owner User' } },
        { 'id' => 'mem_team_1', 'email' => 'team1@test.com',
          'full_name' => { 'sys_root' => 'Team User 1' } },
        { 'id' => 'mem_team_2', 'email' => 'team2@test.com',
          'full_name' => { 'sys_root' => 'Team User 2' } }
      ]
    }

    call_count = 0
    client.define_singleton_method(:api_request) do |_method, endpoint, _body = nil|
      call_count += 1
      if endpoint.include?('solutions')
        solution_response
      elsif endpoint.include?('teams')
        team_response
      else
        members_response
      end
    end

    result = client.list_members(solution_id: 'sol_123')

    # Should include all members: direct, owner, and team members
    assert_equal 4, result['count']
    member_ids = result['members'].map { |m| m['id'] }
    assert_includes member_ids, 'mem_direct'
    assert_includes member_ids, 'mem_owner'
    assert_includes member_ids, 'mem_team_1'
    assert_includes member_ids, 'mem_team_2'
  end

  def test_list_members_by_solution_with_no_permissions
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    solution_response = {
      'id' => 'sol_123',
      'permissions' => nil
    }

    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      solution_response
    end

    result = client.list_members(solution_id: 'sol_123')

    assert_equal 0, result['count']
    assert_equal [], result['members']
  end

  # ========== list_teams cache tests ==========

  def test_list_teams_uses_cache_when_available
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache
    cached_teams = [
      { 'id' => 'team_cached', 'name' => 'Cached Team', 'members' => ['m1'] }
    ]
    client.cache.cache_teams(cached_teams)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.list_teams

    refute api_called, 'Should use cache when teams are cached'
    assert_equal 1, result.size
    assert_equal 'team_cached', result[0]['id']
  end

  def test_get_team_uses_cache_when_available
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate caches
    cached_teams = [
      { 'id' => 'team_cached', 'name' => 'Cached Team', 'description' => 'Test', 'members' => ['mem_1'] }
    ]
    cached_members = [
      formatted_member(id: 'mem_1', email: 'test@test.com', first_name: 'Test', last_name: 'User')
    ]
    client.cache.cache_teams(cached_teams)
    client.cache.cache_members(cached_members)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.get_team('team_cached')

    refute api_called, 'Should use cache when team is cached'
    assert_equal 'team_cached', result['id']
    assert_equal 'Cached Team', result['name']
    assert_equal 1, result['member_count']
  end

  # ========== search_member include_inactive tests ==========

  def test_search_member_with_include_inactive_from_cache
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache with active and deleted members
    cached_members = [
      formatted_member(id: 'mem_active', email: 'active@test.com', first_name: 'Active', last_name: 'User'),
      formatted_member(id: 'mem_deleted', email: 'deleted@test.com', first_name: 'Deleted', last_name: 'User',
                       deleted_date: '2024-01-01')
    ]
    client.cache.cache_members(cached_members)

    # Without include_inactive - should only find active
    result_active = client.search_member('User', include_inactive: false)
    assert_equal 1, result_active['count']
    assert_equal 'mem_active', result_active['members'][0]['id']

    # With include_inactive - should find both
    result_all = client.search_member('User', include_inactive: true)
    assert_equal 2, result_all['count']
  end
end
