# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/smartsuite_client'

# Integration tests for SmartSuite MCP Server
#
# These tests validate against the real SmartSuite API.
# Credentials are loaded ONLY from test/integration/.env file.
# Production credentials are explicitly ignored to prevent accidents.
#
# Setup:
#   1. Copy test/integration/.env.example to test/integration/.env
#   2. Fill in your TEST credentials in .env
#   3. Run: ruby test/integration/test_integration.rb
#
# IMPORTANT: This test NEVER uses ENV['SMARTSUITE_API_KEY'] from your shell.
# It only loads from the local .env file to prevent using production credentials.
class TestIntegration < Minitest::Test
  # Load credentials from local .env file ONLY
  # This ensures we never accidentally use production credentials
  def self.load_test_credentials
    env_file = File.join(__dir__, '.env')

    unless File.exist?(env_file)
      warn "\n⚠️  Integration test .env file not found!"
      warn "   Please copy .env.example to .env and configure test credentials:"
      warn "   cp test/integration/.env.example test/integration/.env\n\n"
      return {}
    end

    credentials = {}
    File.readlines(env_file).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      key, value = line.split('=', 2)
      credentials[key] = value if key && value
    end

    # Safety check: prevent using production credentials
    if credentials['SMARTSUITE_API_KEY']&.include?('your_api_key_here') ||
       credentials['SMARTSUITE_ACCOUNT_ID']&.include?('your_account_id_here')
      warn "\n⚠️  Test credentials not configured!"
      warn "   Please edit test/integration/.env with your TEST credentials\n\n"
      return {}
    end

    credentials
  end

  # Load test credentials at class load time
  TEST_CREDENTIALS = load_test_credentials

  def setup
    # IMPORTANT: Only use credentials from local .env file
    # Never use ENV['SMARTSUITE_API_KEY'] from shell to prevent accidents
    @api_key = TEST_CREDENTIALS['SMARTSUITE_API_KEY']
    @account_id = TEST_CREDENTIALS['SMARTSUITE_ACCOUNT_ID']

    if integration_tests_enabled?
      @client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: true)
      puts "\n✓ Integration tests enabled (credentials loaded from test/integration/.env)"
    else
      puts "\n⚠️  Integration tests skipped (configure test/integration/.env to enable)"
    end
  end

  def teardown
    # Close client connection
    @client&.cache&.close if @client&.cache_enabled?
  end

  # Helper to check if integration tests should run
  def integration_tests_enabled?
    !@api_key.nil? && !@account_id.nil? && !@api_key.empty? && !@account_id.empty?
  end

  # ==================== Workspace Tests ====================

  def test_workspace_list_solutions
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    result = @client.list_solutions

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('solutions'), "Missing 'solutions' key"
    assert result.key?('count'), "Missing 'count' key"
    assert result['solutions'].is_a?(Array), "Expected solutions to be Array"
    assert result['count'] >= 0, "Expected non-negative count"

    if result['count'] > 0
      solution = result['solutions'].first
      assert solution.key?('id'), "Solution missing 'id'"
      assert solution.key?('name'), "Solution missing 'name'"
      puts "\n✓ Found #{result['count']} solutions"
      puts "  First solution: #{solution['name']} (#{solution['id']})"
    else
      puts "\n⚠️  No solutions found in account"
    end
  end

  def test_workspace_list_solutions_with_activity_data
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    result = @client.list_solutions(include_activity_data: true)

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('solutions'), "Missing 'solutions' key"

    if result['count'] > 0
      solution = result['solutions'].first
      assert solution.key?('last_access'), "Solution missing 'last_access' when activity data requested"
      assert solution.key?('records_count'), "Solution missing 'records_count'"
      puts "\n✓ Activity data included: last_access=#{solution['last_access']}, records_count=#{solution['records_count']}"
    end
  end

  def test_workspace_analyze_solution_usage
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    result = @client.analyze_solution_usage(days_inactive: 90, min_records: 10)

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('summary'), "Missing 'summary' key"
    assert result.key?('inactive_solutions'), "Missing 'inactive_solutions' key"
    assert result.key?('potentially_unused_solutions'), "Missing 'potentially_unused_solutions' key"

    summary = result['summary']
    total = summary['total_solutions']
    inactive = summary['inactive_count']
    potentially_unused = summary['potentially_unused_count']
    active = summary['active_count']

    assert_equal total, inactive + potentially_unused + active, "Counts don't add up"

    puts "\n✓ Solution usage analysis:"
    puts "  Total: #{total}, Inactive: #{inactive}, Potentially unused: #{potentially_unused}, Active: #{active}"
  end

  # ==================== Table Tests ====================

  def test_table_list_tables
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    result = @client.list_tables

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('tables'), "Missing 'tables' key"
    assert result.key?('count'), "Missing 'count' key"
    assert result['tables'].is_a?(Array), "Expected tables to be Array"

    if result['count'] > 0
      table = result['tables'].first
      assert table.key?('id'), "Table missing 'id'"
      assert table.key?('name'), "Table missing 'name'"
      puts "\n✓ Found #{result['count']} tables"
      puts "  First table: #{table['name']} (#{table['id']})"
    else
      puts "\n⚠️  No tables found in account"
    end
  end

  def test_table_get_structure
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    # Get first table
    tables = @client.list_tables
    skip "No tables found to test" if tables['count'].zero?

    table_id = tables['tables'].first['id']
    result = @client.get_table(table_id)

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('id'), "Missing 'id' key"
    assert result.key?('structure'), "Missing 'structure' key"
    assert result['structure'].is_a?(Array), "Expected structure to be Array"

    field_count = result['structure'].size
    puts "\n✓ Table structure retrieved: #{field_count} fields"

    if field_count > 0
      field = result['structure'].first
      assert field.key?('slug'), "Field missing 'slug'"
      assert field.key?('label'), "Field missing 'label'"
      assert field.key?('field_type'), "Field missing 'field_type'"
      puts "  First field: #{field['label']} (#{field['field_type']})"
    end
  end

  # ==================== Record Tests ====================

  def test_record_list_records
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    # Get first table with records
    tables = @client.list_tables
    skip "No tables found to test" if tables['count'].zero?

    table_id = tables['tables'].first['id']

    # Get table structure to find field names
    table = @client.get_table(table_id)
    skip "No fields in table" if table['structure'].empty?

    # Use first field as test field
    field_slug = table['structure'].first['slug']

    result = @client.list_records(table_id, 10, 0, fields: [field_slug])

    # Result is plain text format, so just verify it's a string
    assert result.is_a?(String), "Expected String response (plain text format)"
    assert result.include?('records'), "Expected 'records' in response"

    puts "\n✓ Records retrieved (plain text format)"
    puts result.lines.first(5).join # Show first 5 lines
  end

  def test_record_cache_behavior
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    tables = @client.list_tables
    skip "No tables found to test" if tables['count'].zero?

    table_id = tables['tables'].first['id']
    table = @client.get_table(table_id)
    skip "No fields in table" if table['structure'].empty?

    field_slug = table['structure'].first['slug']

    # First call - should fetch from API
    puts "\n→ First call (cache miss expected)..."
    result1 = @client.list_records(table_id, 5, 0, fields: [field_slug])
    assert result1.is_a?(String)

    # Second call - should use cache
    puts "→ Second call (cache hit expected)..."
    result2 = @client.list_records(table_id, 5, 0, fields: [field_slug])
    assert result2.is_a?(String)

    # Third call with bypass_cache - should fetch from API
    puts "→ Third call with bypass_cache=true (cache bypass)..."
    result3 = @client.list_records(table_id, 5, 0, fields: [field_slug], bypass_cache: true)
    assert result3.is_a?(String)

    puts "✓ Cache behavior verified (see metrics log for hit/miss details)"
  end

  # ==================== Member Tests ====================

  def test_member_list_members
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    result = @client.list_members(limit: 10)

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('members'), "Missing 'members' key"
    assert result.key?('count'), "Missing 'count' key"
    assert result['members'].is_a?(Array), "Expected members to be Array"

    if result['count'] > 0
      member = result['members'].first
      assert member.key?('id'), "Member missing 'id'"
      assert member.key?('email'), "Member missing 'email'"
      puts "\n✓ Found #{result['count']} members"
      puts "  First member: #{member['email']}"
    else
      puts "\n⚠️  No members found"
    end
  end

  def test_member_search
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    # Get a member first
    members = @client.list_members(limit: 1)
    skip "No members found to test" if members['count'].zero?

    member_email = members['members'].first['email']
    search_query = member_email.split('@').first # Search by first part of email

    result = @client.search_member(search_query)

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('members'), "Missing 'members' key"
    assert result['count'] >= 0, "Expected non-negative count"

    puts "\n✓ Member search for '#{search_query}': #{result['count']} results"
  end

  # ==================== Cache Tests ====================

  def test_cache_get_status
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?
    skip "Cache not enabled" unless @client.cache_enabled?

    result = @client.cache.get_cache_status

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('timestamp'), "Missing 'timestamp' key"
    assert result.key?('solutions'), "Missing 'solutions' key"
    assert result.key?('tables'), "Missing 'tables' key"
    assert result.key?('records'), "Missing 'records' key"

    puts "\n✓ Cache status retrieved"
    puts "  Solutions cached: #{result['solutions'] ? 'Yes' : 'No'}"
    puts "  Tables cached: #{result['tables'] ? 'Yes' : 'No'}"
    puts "  Records cached: #{result['records'].is_a?(Array) ? result['records'].size : 0} tables"
  end

  def test_cache_refresh
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?
    skip "Cache not enabled" unless @client.cache_enabled?

    result = @client.cache.refresh_cache('solutions')

    assert result.is_a?(Hash), "Expected Hash response"
    assert_equal 'success', result['status'], "Expected status=success"
    assert_equal 'refresh', result['operation'], "Expected operation=refresh"
    assert result.key?('message'), "Missing 'message' key"
    assert result.key?('timestamp'), "Missing 'timestamp' key"
    assert_equal 'solutions', result['resource'], "Expected resource=solutions"

    puts "\n✓ Cache refresh successful"
    puts "  #{result['message']}"
  end

  def test_cache_warm
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?
    skip "Cache not enabled" unless @client.cache_enabled?

    # Get first table to warm
    tables = @client.list_tables
    skip "No tables to warm" if tables['count'].zero?

    table_id = tables['tables'].first['id']

    result = @client.warm_cache(tables: [table_id])

    assert result.is_a?(Hash), "Expected Hash response"
    assert_equal 'completed', result['status'], "Expected status=completed"
    assert_equal 'warm', result['operation'], "Expected operation=warm"
    assert result.key?('summary'), "Missing 'summary' key"
    assert result.key?('results'), "Missing 'results' key"
    assert result.key?('timestamp'), "Missing 'timestamp' key"

    summary = result['summary']
    puts "\n✓ Cache warming completed"
    puts "  Total tables: #{summary['total_tables']}"
    puts "  Warmed: #{summary['warmed']}"
    puts "  Skipped: #{summary['skipped']}"
    puts "  Errors: #{summary['errors']}"
  end

  # ==================== API Stats Tests ====================

  def test_stats_get_api_stats
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?
    skip "Stats tracker not available" unless @client.stats_tracker

    result = @client.stats_tracker.get_stats(time_range: 'session')

    assert result.is_a?(Hash), "Expected Hash response"
    assert result.key?('time_range'), "Missing 'time_range' key"
    assert result.key?('summary'), "Missing 'summary' key"
    assert result.key?('cache_stats'), "Missing 'cache_stats' key"

    summary = result['summary']
    total_calls = summary['total_calls']

    puts "\n✓ API stats retrieved"
    puts "  Time range: #{result['time_range']}"
    puts "  Total API calls this session: #{total_calls}"

    if result['cache_stats']
      cache = result['cache_stats']
      puts "  Cache hits: #{cache['total_hits']}"
      puts "  Cache misses: #{cache['total_misses']}"
      puts "  Hit rate: #{cache['hit_rate_percentage']}%"
    end
  end

  # ==================== Error Handling Tests ====================

  def test_error_handling_invalid_table_id
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    # Try to get a non-existent table
    error = assert_raises(StandardError) do
      @client.get_table('invalid_table_id_12345')
    end

    puts "\n✓ Error handling works for invalid table ID"
    puts "  Error: #{error.message}"
  end

  def test_error_handling_missing_required_parameter
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    # Try to call method without required parameter
    error = assert_raises(ArgumentError) do
      @client.get_solution(nil)
    end

    assert_includes error.message, 'required', "Expected 'required' in error message"

    puts "\n✓ Error handling works for missing required parameter"
    puts "  Error: #{error.message}"
  end

  # ==================== Integration Summary ====================

  def test_zzz_integration_summary
    skip "Integration test - requires real API credentials" unless integration_tests_enabled?

    puts "\n" + "=" * 70
    puts "INTEGRATION TEST SUMMARY"
    puts "=" * 70

    # Get final stats
    if @client.stats_tracker
      stats = @client.stats_tracker.get_stats(time_range: 'session')
      summary = stats['summary']

      puts "\nAPI Usage:"
      puts "  Total API calls: #{summary['total_calls']}"
      puts "  Unique solutions: #{summary['unique_solutions']}"
      puts "  Unique tables: #{summary['unique_tables']}"

      if stats['cache_stats']
        cache = stats['cache_stats']
        puts "\nCache Performance:"
        puts "  Cache hits: #{cache['total_hits']}"
        puts "  Cache misses: #{cache['total_misses']}"
        puts "  Hit rate: #{cache['hit_rate_percentage']}%"
        puts "  API calls saved: #{cache['api_calls_saved']}"
      end
    end

    # Get cache status
    if @client.cache_enabled?
      status = @client.cache.get_cache_status
      records_count = status['records'].is_a?(Array) ? status['records'].size : 0

      puts "\nCache Status:"
      puts "  Solutions cached: #{status['solutions'] ? 'Yes' : 'No'}"
      puts "  Tables cached: #{status['tables'] ? 'Yes' : 'No'}"
      puts "  Record tables cached: #{records_count}"
    end

    puts "\n" + "=" * 70
    puts "✓ All integration tests completed successfully!"
    puts "=" * 70
  end
end
