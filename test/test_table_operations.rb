# frozen_string_literal: true

require_relative 'test_helper'
require 'net/http'
require 'fileutils'
require_relative '../lib/smartsuite_client'

class TestTableOperations < Minitest::Test
  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    # Use a unique temp cache path for each test run
    @test_cache_path = File.join(Dir.tmpdir, "test_table_ops_#{rand(100_000)}.db")
  end

  def teardown
    # Clean up test cache file
    FileUtils.rm_f(@test_cache_path) if @test_cache_path && File.exist?(@test_cache_path)
  end

  # Helper to create a fresh client with mocked api_request
  def create_mock_client(&block)
    client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)
    client.define_singleton_method(:api_request, &block) if block_given?
    client
  end

  # ========== list_tables tests ==========

  def test_list_tables_success
    expected_response = [
      { 'id' => 'tbl_1', 'name' => 'Table 1', 'solution' => 'sol_123' },
      { 'id' => 'tbl_2', 'name' => 'Table 2', 'solution' => 'sol_123' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_tables

    assert result.is_a?(Hash)
    assert_equal 2, result['count']
    assert_equal 2, result['tables'].size
    assert_equal 'tbl_1', result['tables'][0]['id']
  end

  def test_list_tables_filters_essential_fields
    # API returns lots of fields, but we filter to essentials
    expected_response = [
      {
        'id' => 'tbl_1',
        'name' => 'Table 1',
        'solution' => 'sol_123',
        'slug' => 'table-1',
        'icon' => 'icon-code',
        'status' => 'active',
        'permissions' => { 'owners' => ['user1'] },
        'structure' => [{ 'slug' => 'title' }]
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_tables

    table = result['tables'][0]
    # Should only have essential fields
    assert_equal 'tbl_1', table['id']
    assert_equal 'Table 1', table['name']
    assert_equal 'sol_123', table['solution_id'] # Normalized from 'solution'
    # These should NOT be present
    refute table.key?('slug'), 'Should not include slug without explicit fields'
    refute table.key?('icon'), 'Should not include icon without explicit fields'
    refute table.key?('structure'), 'Should not include structure without explicit fields'
  end

  def test_list_tables_with_solution_id_filter
    solution_id = 'sol_456'
    endpoint_called = nil

    client = create_mock_client do |_method, endpoint, _body = nil|
      endpoint_called = endpoint
      []
    end

    client.list_tables(solution_id: solution_id)

    assert_includes endpoint_called, "solution=#{solution_id}"
  end

  def test_list_tables_with_specific_fields
    fields = %w[id name structure]
    endpoint_called = nil

    client = create_mock_client do |_method, endpoint, _body = nil|
      endpoint_called = endpoint
      []
    end

    client.list_tables(fields: fields)

    # Fields should be passed as repeated query params
    fields.each do |field|
      assert_includes endpoint_called, "fields=#{field}"
    end
  end

  def test_list_tables_with_fields_returns_full_response
    # When specific fields are requested, return full response (no client-side filtering)
    expected_response = [
      {
        'id' => 'tbl_1',
        'name' => 'Table 1',
        'structure' => [{ 'slug' => 'title', 'field_type' => 'textfield' }]
      }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_tables(fields: %w[id name structure])

    table = result['tables'][0]
    assert table.key?('structure'), 'Should include structure when explicitly requested'
    assert_equal 1, table['structure'].length
  end

  def test_list_tables_validates_fields_parameter_type
    client = create_mock_client
    assert_raises(ArgumentError) do
      client.list_tables(fields: 'not_an_array')
    end
  end

  def test_list_tables_normalizes_solution_key
    # API returns 'solution' but we normalize to 'solution_id'
    expected_response = [
      { 'id' => 'tbl_1', 'name' => 'Table', 'solution' => 'sol_abc' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_tables

    table = result['tables'][0]
    assert_equal 'sol_abc', table['solution_id']
    refute table.key?('solution'), 'Should normalize solution to solution_id'
  end

  def test_list_tables_handles_solution_id_key
    # Some cached results have 'solution_id' instead of 'solution'
    expected_response = [
      { 'id' => 'tbl_1', 'name' => 'Table', 'solution_id' => 'sol_xyz' }
    ]

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.list_tables

    assert_equal 'sol_xyz', result['tables'][0]['solution_id']
  end

  # ========== get_table tests ==========

  def test_get_table_success
    table_id = 'tbl_123'
    expected_response = {
      'id' => table_id,
      'name' => 'Test Table',
      'solution' => 'sol_456',
      'structure' => [
        {
          'slug' => 'title',
          'label' => 'Title',
          'field_type' => 'textfield',
          'required' => true,
          'help_doc' => { 'html' => 'Help text' },
          'display_format' => 'default'
        }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.get_table(table_id)

    assert_equal table_id, result['id']
    assert_equal 'Test Table', result['name']
    assert_equal 'sol_456', result['solution_id']
    assert_equal 1, result['structure'].length
  end

  def test_get_table_filters_structure_fields
    table_id = 'tbl_filter'
    expected_response = {
      'id' => table_id,
      'name' => 'Table',
      'solution' => 'sol_1',
      'structure' => [
        {
          'slug' => 'status',
          'label' => 'Status',
          'field_type' => 'statusfield',
          'required' => false,
          # These should be filtered out:
          'help_doc' => { 'html' => 'Status help' },
          'display_format' => 'pill',
          'width' => 150,
          'column_widths' => { 'grid' => 150, 'kanban' => 100 },
          'default_value' => 'active'
        }
      ]
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.get_table(table_id)

    field = result['structure'][0]
    # Essential fields should be present
    assert_equal 'status', field['slug']
    assert_equal 'Status', field['label']
    assert_equal 'statusfield', field['field_type']
  end

  def test_get_table_missing_table_id
    client = create_mock_client
    assert_raises(ArgumentError, 'table_id is required') do
      client.get_table(nil)
    end

    assert_raises(ArgumentError, 'table_id is required') do
      client.get_table('')
    end
  end

  def test_get_table_api_endpoint
    table_id = 'tbl_endpoint_test'
    endpoint_called = nil

    client = create_mock_client do |_method, endpoint, _body = nil|
      endpoint_called = endpoint
      { 'id' => table_id, 'name' => 'Table', 'structure' => [] }
    end

    client.get_table(table_id)

    assert_equal "/applications/#{table_id}/", endpoint_called
  end

  def test_get_table_normalizes_solution_key
    table_id = 'tbl_norm'
    expected_response = {
      'id' => table_id,
      'name' => 'Table',
      'solution' => 'sol_original',
      'structure' => []
    }

    client = create_mock_client { |_method, _endpoint, _body = nil| expected_response }
    result = client.get_table(table_id)

    assert_equal 'sol_original', result['solution_id']
    refute result.key?('solution'), 'Should normalize solution to solution_id'
  end

  def test_get_table_handles_non_hash_response
    table_id = 'tbl_error'

    client = create_mock_client { |_method, _endpoint, _body = nil| 'Error response string' }
    result = client.get_table(table_id)

    assert_equal 'Error response string', result
  end

  # ========== create_table tests ==========

  def test_create_table_success
    solution_id = 'sol_new'
    name = 'New Table'

    expected_response = {
      'id' => 'tbl_created',
      'name' => name,
      'solution' => solution_id,
      'structure' => []
    }

    body_sent = nil
    client = create_mock_client do |_method, _endpoint, body = nil|
      body_sent = body
      expected_response
    end

    result = client.create_table(solution_id, name)

    assert_equal 'tbl_created', result['id']
    assert_equal name, result['name']
    assert_equal solution_id, body_sent['solution']
    assert_equal name, body_sent['name']
    assert_equal [], body_sent['structure']
  end

  def test_create_table_with_description
    solution_id = 'sol_desc'
    name = 'Described Table'
    description = 'This table has a description'

    body_sent = nil
    client = create_mock_client do |_method, _endpoint, body = nil|
      body_sent = body
      { 'id' => 'tbl_desc', 'name' => name }
    end

    client.create_table(solution_id, name, description: description)

    assert_equal description, body_sent['description']
  end

  def test_create_table_with_structure
    solution_id = 'sol_struct'
    name = 'Structured Table'
    structure = [
      { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
      { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield' }
    ]

    body_sent = nil
    client = create_mock_client do |_method, _endpoint, body = nil|
      body_sent = body
      { 'id' => 'tbl_struct', 'name' => name }
    end

    client.create_table(solution_id, name, structure: structure)

    assert_equal structure, body_sent['structure']
  end

  def test_create_table_missing_solution_id
    client = create_mock_client
    assert_raises(ArgumentError, 'solution_id is required') do
      client.create_table(nil, 'Table Name')
    end

    assert_raises(ArgumentError, 'solution_id is required') do
      client.create_table('', 'Table Name')
    end
  end

  def test_create_table_missing_name
    client = create_mock_client
    assert_raises(ArgumentError, 'name is required') do
      client.create_table('sol_123', nil)
    end

    assert_raises(ArgumentError, 'name is required') do
      client.create_table('sol_123', '')
    end
  end

  def test_create_table_validates_structure_type
    client = create_mock_client
    assert_raises(ArgumentError) do
      client.create_table('sol_123', 'Table', structure: 'not_an_array')
    end
  end

  def test_create_table_api_endpoint
    solution_id = 'sol_ep'
    name = 'Endpoint Test'

    endpoint_called = nil
    method_called = nil

    client = create_mock_client do |method, endpoint, _body = nil|
      endpoint_called = endpoint
      method_called = method
      { 'id' => 'tbl_ep', 'name' => name }
    end

    client.create_table(solution_id, name)

    assert_equal '/applications/', endpoint_called
    assert_equal :post, method_called
  end

  # ========== Cache-related tests ==========

  def test_list_tables_uses_cache_when_available
    # Create client with cache enabled
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache with table list
    cached_tables = [
      { 'id' => 'tbl_cached_1', 'name' => 'Cached Table 1', 'solution' => 'sol_123' },
      { 'id' => 'tbl_cached_2', 'name' => 'Cached Table 2', 'solution' => 'sol_123' }
    ]
    client.cache.cache_table_list(nil, cached_tables)

    # Should return cached data without hitting API
    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API when cache is valid'
    end

    result = client.list_tables

    refute api_called, 'Should not call API when cache is valid'
    assert_equal 2, result['count']
    assert_equal 'tbl_cached_1', result['tables'][0]['id']
  end

  def test_list_tables_caches_api_response
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Mock API response
    api_response = [
      { 'id' => 'tbl_api_1', 'name' => 'API Table 1', 'solution' => 'sol_456' }
    ]
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_response
    end

    # First call - should cache
    result = client.list_tables
    assert_equal 1, result['count']

    # Verify it's cached by checking cache directly
    cached = client.cache.get_cached_table_list(nil)
    assert cached, 'Should have cached the table list'
    assert_equal 1, cached.size
  end

  def test_list_tables_with_solution_id_uses_cache
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)
    solution_id = 'sol_specific'

    # Pre-populate cache with solution-specific tables
    cached_tables = [
      { 'id' => 'tbl_sol_1', 'name' => 'Solution Table', 'solution' => solution_id }
    ]
    client.cache.cache_table_list(solution_id, cached_tables)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.list_tables(solution_id: solution_id)

    refute api_called, 'Should use cache for solution-specific tables'
    assert_equal 1, result['count']
  end

  def test_get_table_uses_cache_when_available
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)
    table_id = 'tbl_get_cached'

    # Pre-populate cache with table via cache_table_list (which populates cached_tables SQL table)
    cached_tables = [{
      'id' => table_id,
      'name' => 'Cached Table',
      'solution' => 'sol_123',
      'structure' => [
        { 'slug' => 'title', 'label' => 'Title', 'field_type' => 'textfield' },
        { 'slug' => 'status', 'label' => 'Status', 'field_type' => 'statusfield' }
      ]
    }]
    client.cache.cache_table_list(nil, cached_tables)

    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      raise 'Should not call API'
    end

    result = client.get_table(table_id)

    refute api_called, 'Should use cache when table is cached'
    assert_equal table_id, result['id']
    assert_equal 'Cached Table', result['name']
    assert result['structure'], 'Should include filtered structure'
  end

  def test_list_tables_bypasses_cache_when_fields_specified
    client = SmartSuiteClient.new(@api_key, @account_id, cache_path: @test_cache_path)

    # Pre-populate cache
    cached_tables = [{ 'id' => 'tbl_cached', 'name' => 'Cached' }]
    client.cache.cache_table_list(nil, cached_tables)

    # Mock API response
    api_response = [{ 'id' => 'tbl_api', 'name' => 'From API', 'structure' => [] }]
    api_called = false
    client.define_singleton_method(:api_request) do |_method, _endpoint, _body = nil|
      api_called = true
      api_response
    end

    # When fields is specified, should bypass cache
    result = client.list_tables(fields: %w[id name structure])

    assert api_called, 'Should call API when specific fields requested'
    assert_equal 'tbl_api', result['tables'][0]['id']
  end
end
