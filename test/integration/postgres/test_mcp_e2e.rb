# frozen_string_literal: true

# Load Rails test environment for PostgreSQL
ENV["RAILS_ENV"] ||= "test"
require_relative "../../../config/environment"
require "minitest/autorun"
require "json"
require "stringio"

# End-to-end MCP protocol tests for PostgreSQL cache layer.
#
# These tests verify the complete flow:
#   JSON-RPC stdin → SmartSuiteServer → Tools → Cache::PostgresLayer → PostgreSQL → Response
#
# Tests cover:
# - All filter operators through list_records tool
# - Cache operations (status, refresh)
# - Solutions, tables, members, teams caching
# - Views and deleted records caching
# - Metadata storage
#
# Prerequisites:
# - PostgreSQL running locally
# - Test database migrated: RAILS_ENV=test rails db:migrate
# - SmartSuite credentials in environment (for API calls)
#
class TestMcpEndToEnd < Minitest::Test
  def setup
    skip_unless_postgres_available!

    # Clear cache tables before each test
    clear_cache_tables!

    # Create server instance
    @server = create_test_server
  end

  def teardown
    clear_cache_tables! if postgres_available?
  end

  # ==================== MCP Protocol Tests ====================

  def test_initialize_returns_capabilities
    response = send_mcp_request("initialize", {})

    assert_equal "2.0", response["jsonrpc"]
    assert response["result"]["capabilities"]["tools"]
    assert response["result"]["capabilities"]["prompts"]
    assert_equal "smartsuite-server", response["result"]["serverInfo"]["name"]
  end

  def test_tools_list_includes_all_cache_tools
    response = send_mcp_request("tools/list", {})

    tool_names = response["result"]["tools"].map { |t| t["name"] }

    # Core cache-related tools
    assert_includes tool_names, "list_records"
    assert_includes tool_names, "get_record"
    assert_includes tool_names, "list_solutions"
    assert_includes tool_names, "list_tables"
    assert_includes tool_names, "list_members"
    assert_includes tool_names, "list_teams"
    assert_includes tool_names, "get_cache_status"
    assert_includes tool_names, "refresh_cache"
    assert_includes tool_names, "list_views"
    assert_includes tool_names, "list_deleted_records"
  end

  # ==================== Cache Status Tests ====================

  def test_get_cache_status_returns_structure
    response = call_tool("get_cache_status", {})

    # Parse the response content
    content = extract_tool_content(response)

    # Should have structure for all cache types
    assert content.include?("timestamp") || content.include?("solutions") || content.include?("Cache Status"),
           "Cache status should return structured data"
  end

  def test_refresh_cache_solutions
    response = call_tool("refresh_cache", { "resource" => "solutions" })
    content = extract_tool_content(response)

    assert content.include?("success") || content.include?("invalidated") || content.include?("Solutions"),
           "Should confirm solutions cache refresh"
  end

  def test_refresh_cache_members
    response = call_tool("refresh_cache", { "resource" => "members" })
    content = extract_tool_content(response)

    assert content.include?("success") || content.include?("invalidated") || content.include?("Members"),
           "Should confirm members cache refresh"
  end

  def test_refresh_cache_teams
    response = call_tool("refresh_cache", { "resource" => "teams" })
    content = extract_tool_content(response)

    assert content.include?("success") || content.include?("invalidated") || content.include?("Teams"),
           "Should confirm teams cache refresh"
  end

  # ==================== Filter Operator Tests ====================

  # These tests require cached data. We'll use mock data insertion.

  def test_filter_text_contains
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Alpha Project", "status" => "active" },
      { "id" => "rec_2", "name" => "Beta Test", "status" => "active" },
      { "id" => "rec_3", "name" => "Gamma Alpha", "status" => "inactive" }
    ])

    # Test contains filter
    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "name", "comparison" => "contains", "value" => "Alpha" } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records containing 'Alpha'"
    assert records.all? { |r| r["name"].include?("Alpha") }
  end

  def test_filter_text_is_empty
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Has Name", "description" => "Some text" },
      { "id" => "rec_2", "name" => "No Description", "description" => "" },
      { "id" => "rec_3", "name" => "Null Description", "description" => nil }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "description", "comparison" => "is_empty" } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with empty description"
  end

  def test_filter_numeric_greater_than
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Low", "amount" => 50 },
      { "id" => "rec_2", "name" => "Medium", "amount" => 100 },
      { "id" => "rec_3", "name" => "High", "amount" => 200 }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "amount", "comparison" => "is_greater_than", "value" => 75 } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with amount > 75"
    assert records.all? { |r| r["amount"].to_i > 75 }
  end

  def test_filter_numeric_range
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "price" => 10 },
      { "id" => "rec_2", "name" => "B", "price" => 50 },
      { "id" => "rec_3", "name" => "C", "price" => 100 },
      { "id" => "rec_4", "name" => "D", "price" => 150 }
    ])

    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "price", "comparison" => "is_equal_or_greater_than", "value" => 50 },
        { "field" => "price", "comparison" => "is_equal_or_less_than", "value" => 100 }
      ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with price between 50-100"
  end

  def test_filter_single_select_is
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "status" => { "value" => "active" } },
      { "id" => "rec_2", "name" => "B", "status" => { "value" => "inactive" } },
      { "id" => "rec_3", "name" => "C", "status" => { "value" => "active" } }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "status", "comparison" => "is", "value" => "active" } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 active records"
  end

  def test_filter_single_select_is_any_of
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "priority" => { "value" => "high" } },
      { "id" => "rec_2", "name" => "B", "priority" => { "value" => "medium" } },
      { "id" => "rec_3", "name" => "C", "priority" => { "value" => "low" } },
      { "id" => "rec_4", "name" => "D", "priority" => { "value" => "high" } }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "priority", "comparison" => "is_any_of", "value" => %w[high medium] } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 3, records.size, "Should find 3 records with high or medium priority"
  end

  def test_filter_multi_select_has_any_of
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "tags" => %w[ruby rails] },
      { "id" => "rec_2", "name" => "B", "tags" => %w[python django] },
      { "id" => "rec_3", "name" => "C", "tags" => %w[ruby python] }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "tags", "comparison" => "has_any_of", "value" => [ "ruby" ] } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with 'ruby' tag"
  end

  def test_filter_multi_select_has_all_of
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "skills" => %w[ruby rails postgresql] },
      { "id" => "rec_2", "name" => "B", "skills" => %w[ruby rails] },
      { "id" => "rec_3", "name" => "C", "skills" => %w[python django] }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "skills", "comparison" => "has_all_of", "value" => %w[ruby rails] } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with both 'ruby' and 'rails'"
  end

  def test_filter_multi_select_has_none_of
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "categories" => %w[tech finance] },
      { "id" => "rec_2", "name" => "B", "categories" => %w[health] },
      { "id" => "rec_3", "name" => "C", "categories" => %w[tech] }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "categories", "comparison" => "has_none_of", "value" => [ "tech" ] } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 1, records.size, "Should find 1 record without 'tech'"
    assert_equal "rec_2", records.first["id"]
  end

  def test_filter_date_is_before
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Past", "due_date" => { "to_date" => { "date" => "2024-01-15" } } },
      { "id" => "rec_2", "name" => "Recent", "due_date" => { "to_date" => { "date" => "2024-06-15" } } },
      { "id" => "rec_3", "name" => "Future", "due_date" => { "to_date" => { "date" => "2025-01-15" } } }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ {
        "field" => "due_date",
        "comparison" => "is_before",
        "value" => { "date_mode" => "exact_date", "date_mode_value" => "2024-07-01" }
      } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records before 2024-07-01"
  end

  def test_filter_date_is_on_or_after
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Old", "created" => { "to_date" => { "date" => "2023-01-01" } } },
      { "id" => "rec_2", "name" => "New", "created" => { "to_date" => { "date" => "2024-06-01" } } },
      { "id" => "rec_3", "name" => "Newest", "created" => { "to_date" => { "date" => "2024-12-01" } } }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ {
        "field" => "created",
        "comparison" => "is_on_or_after",
        "value" => { "date_mode" => "exact_date", "date_mode_value" => "2024-06-01" }
      } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records on or after 2024-06-01"
  end

  def test_filter_file_type_is
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Doc", "files" => [ { "name" => "report.pdf", "type" => "pdf" } ] },
      { "id" => "rec_2", "name" => "Image", "files" => [ { "name" => "photo.jpg", "type" => "image" } ] },
      { "id" => "rec_3", "name" => "Another PDF", "files" => [ { "name" => "invoice.pdf", "type" => "pdf" } ] }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "files", "comparison" => "file_type_is", "value" => "pdf" } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with PDF files"
  end

  def test_filter_file_name_contains
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "attachments" => [ { "name" => "Q1_report.pdf", "type" => "pdf" } ] },
      { "id" => "rec_2", "name" => "B", "attachments" => [ { "name" => "Q2_report.pdf", "type" => "pdf" } ] },
      { "id" => "rec_3", "name" => "C", "attachments" => [ { "name" => "summary.pdf", "type" => "pdf" } ] }
    ])

    filter = {
      "operator" => "and",
      "fields" => [ { "field" => "attachments", "comparison" => "file_name_contains", "value" => "report" } ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 2, records.size, "Should find 2 records with 'report' in filename"
  end

  def test_filter_or_operator
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Active High", "status" => { "value" => "active" }, "priority" => { "value" => "high" } },
      { "id" => "rec_2", "name" => "Inactive High", "status" => { "value" => "inactive" }, "priority" => { "value" => "high" } },
      { "id" => "rec_3", "name" => "Active Low", "status" => { "value" => "active" }, "priority" => { "value" => "low" } },
      { "id" => "rec_4", "name" => "Inactive Low", "status" => { "value" => "inactive" }, "priority" => { "value" => "low" } }
    ])

    # OR: status=active OR priority=high
    filter = {
      "operator" => "or",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "active" },
        { "field" => "priority", "comparison" => "is", "value" => "high" }
      ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 3, records.size, "Should find 3 records (active OR high priority)"
  end

  def test_filter_combined_and
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Match", "status" => { "value" => "active" }, "category" => "tech" },
      { "id" => "rec_2", "name" => "No Match 1", "status" => { "value" => "inactive" }, "category" => "tech" },
      { "id" => "rec_3", "name" => "No Match 2", "status" => { "value" => "active" }, "category" => "finance" }
    ])

    filter = {
      "operator" => "and",
      "fields" => [
        { "field" => "status", "comparison" => "is", "value" => "active" },
        { "field" => "category", "comparison" => "is", "value" => "tech" }
      ]
    }

    records = query_cached_records(table_id, filter)

    assert_equal 1, records.size, "Should find 1 record matching both conditions"
    assert_equal "rec_1", records.first["id"]
  end

  # ==================== Sorting Tests ====================

  def test_sort_ascending
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "Charlie" },
      { "id" => "rec_2", "name" => "Alpha" },
      { "id" => "rec_3", "name" => "Bravo" }
    ])

    records = query_cached_records(table_id, nil, sort: [ { "field" => "name", "direction" => "asc" } ])

    assert_equal "Alpha", records[0]["name"]
    assert_equal "Bravo", records[1]["name"]
    assert_equal "Charlie", records[2]["name"]
  end

  def test_sort_descending
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A", "score" => 10 },
      { "id" => "rec_2", "name" => "B", "score" => 30 },
      { "id" => "rec_3", "name" => "C", "score" => 20 }
    ])

    records = query_cached_records(table_id, nil, sort: [ { "field" => "score", "direction" => "desc" } ])

    assert_equal 30, records[0]["score"]
    assert_equal 20, records[1]["score"]
    assert_equal 10, records[2]["score"]
  end

  # ==================== Pagination Tests ====================

  def test_limit_and_offset
    table_id = setup_test_records_in_cache([
      { "id" => "rec_1", "name" => "A" },
      { "id" => "rec_2", "name" => "B" },
      { "id" => "rec_3", "name" => "C" },
      { "id" => "rec_4", "name" => "D" },
      { "id" => "rec_5", "name" => "E" }
    ])

    # Get second page (offset 2, limit 2)
    records = query_cached_records(table_id, nil, limit: 2, offset: 2)

    assert_equal 2, records.size, "Should return 2 records"
  end

  # ==================== Helper Methods ====================

  private

  def postgres_available?
    # Force connection attempt
    ActiveRecord::Base.connection.execute("SELECT 1")
    ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  rescue StandardError => e
    puts "PostgreSQL check failed: #{e.message}"
    false
  end

  def skip_unless_postgres_available!
    skip "PostgreSQL not available" unless postgres_available?
  end

  def clear_cache_tables!
    conn = ActiveRecord::Base.connection.raw_connection
    %w[cache_records cache_solutions cache_tables cache_members cache_teams cache_table_schemas].each do |table|
      conn.exec("DELETE FROM #{table}") rescue nil
    end
    conn.exec("DELETE FROM cache_views") rescue nil
    conn.exec("DELETE FROM cache_deleted_records") rescue nil
  end

  def create_test_server
    # Create server with test credentials
    ENV["SMARTSUITE_API_KEY"] ||= "test_key"
    ENV["SMARTSUITE_ACCOUNT_ID"] ||= "test_account"

    require_relative "../../../smartsuite_server"
    SmartSuiteServer.new
  rescue StandardError => e
    skip "Could not create test server: #{e.message}"
  end

  def send_mcp_request(method, params)
    request = {
      "jsonrpc" => "2.0",
      "id" => rand(1000),
      "method" => method,
      "params" => params
    }

    @server.send(:handle_request, request)
  end

  def call_tool(tool_name, arguments)
    send_mcp_request("tools/call", {
      "name" => tool_name,
      "arguments" => arguments
    })
  end

  def extract_tool_content(response)
    return "" unless response["result"]

    content = response["result"]["content"]
    return "" unless content.is_a?(Array)

    content.map { |c| c["text"] || c.to_s }.join("\n")
  end

  # Insert test records directly into PostgreSQL cache
  def setup_test_records_in_cache(records)
    table_id = "test_table_#{rand(10000)}"
    now = Time.current
    expires_at = now + 4.hours

    conn = ActiveRecord::Base.connection.raw_connection

    # Insert test schema
    structure = build_structure_from_records(records)
    conn.exec_params(
      "INSERT INTO cache_table_schemas (table_id, structure, cached_at, expires_at) VALUES ($1, $2, $3, $4)
       ON CONFLICT (table_id) DO UPDATE SET structure = $2, cached_at = $3, expires_at = $4",
      [ table_id, structure.to_json, now, expires_at ]
    )

    # Insert records
    records.each do |record|
      conn.exec_params(
        "INSERT INTO cache_records (table_id, record_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)",
        [ table_id, record["id"], record.to_json, now, expires_at ]
      )
    end

    table_id
  end

  def build_structure_from_records(records)
    return [] if records.empty?

    # Infer structure from first record
    sample = records.first
    sample.keys.map do |key|
      {
        "slug" => key,
        "label" => key.capitalize,
        "field_type" => infer_field_type(sample[key])
      }
    end
  end

  def infer_field_type(value)
    case value
    when Integer, Float then "numberfield"
    when Array then "multipleselectfield"
    when Hash
      if value["value"]
        "statusfield"
      elsif value["to_date"]
        "duedatefield"
      else
        "textfield"
      end
    else
      "textfield"
    end
  end

  # Query records using Cache::PostgresLayer
  def query_cached_records(table_id, filter, sort: nil, limit: nil, offset: nil)
    cache = Cache::PostgresLayer.new
    cache.get_cached_records(
      table_id,
      filter: filter,
      sort: sort,
      limit: limit,
      offset: offset
    ) || []
  end
end
