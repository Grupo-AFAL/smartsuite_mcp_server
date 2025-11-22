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
end
