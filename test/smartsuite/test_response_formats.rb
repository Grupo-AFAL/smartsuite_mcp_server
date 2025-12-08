# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/smart_suite/response_formats"

class TestResponseFormats < Minitest::Test
  # Test class that includes ResponseFormats module
  class TestClass
    include SmartSuite::ResponseFormats
  end

  def setup
    @formatter = TestClass.new
  end

  # Test operation_response
  def test_operation_response_basic
    result = @formatter.operation_response("refresh", "Cache invalidated")

    assert_equal "success", result["status"]
    assert_equal "refresh", result["operation"]
    assert_equal "Cache invalidated", result["message"]
    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, result["timestamp"])
  end

  def test_operation_response_with_custom_status
    result = @formatter.operation_response("warm", "Warmed caches", status: "completed")

    assert_equal "completed", result["status"]
    assert_equal "warm", result["operation"]
  end

  def test_operation_response_with_additional_data
    result = @formatter.operation_response(
      "warm",
      "Warmed 3 tables",
      status: "completed",
      warmed: 3,
      skipped: 2,
      total: 5
    )

    assert_equal "completed", result["status"]
    assert_equal 3, result["warmed"]
    assert_equal 2, result["skipped"]
    assert_equal 5, result["total"]
  end

  def test_operation_response_with_symbol_keys
    result = @formatter.operation_response(
      "analyze",
      "Analysis complete",
      inactive_count: 10,
      active_count: 20
    )

    assert_equal 10, result["inactive_count"]
    assert_equal 20, result["active_count"]
  end

  # Test error_response
  def test_error_response_basic
    result = @formatter.error_response("cache_disabled", "Cache is not enabled")

    assert_equal "error", result["status"]
    assert_equal "cache_disabled", result["error"]
    assert_equal "Cache is not enabled", result["message"]
    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, result["timestamp"])
  end

  def test_error_response_with_context
    result = @formatter.error_response(
      "invalid_parameter",
      "table_id is required",
      parameter: "table_id",
      provided: nil
    )

    assert_equal "error", result["status"]
    assert_equal "invalid_parameter", result["error"]
    assert_equal "table_id", result["parameter"]
    assert_nil result["provided"]
  end

  def test_error_response_with_symbol_keys
    result = @formatter.error_response("test_error", "Test", code: 400)

    assert_equal 400, result["code"]
  end

  # Test query_response
  def test_query_response_basic
    result = @formatter.query_response(
      solutions: [ 1, 2, 3 ],
      tables: [ 4, 5, 6 ]
    )

    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, result["timestamp"])
    assert_equal [ 1, 2, 3 ], result["solutions"]
    assert_equal [ 4, 5, 6 ], result["tables"]
  end

  def test_query_response_with_nested_data
    result = @formatter.query_response(
      summary: {
        total: 100,
        active: 80
      },
      by_method: {
        get: 50,
        post: 50
      }
    )

    assert result["summary"].is_a?(Hash)
    assert_equal 100, result["summary"][:total]
    assert_equal 80, result["summary"][:active]
  end

  def test_query_response_with_symbol_keys
    result = @formatter.query_response(count: 42, data: "test")

    assert_equal 42, result["count"]
    assert_equal "test", result["data"]
  end

  def test_query_response_empty
    result = @formatter.query_response

    assert_equal 1, result.keys.size
    assert result.key?("timestamp")
  end

  # Test collection_response
  def test_collection_response_basic
    items = [ { "id" => 1 }, { "id" => 2 } ]
    result = @formatter.collection_response(items, :solutions)

    assert_equal items, result["solutions"]
    assert_equal 2, result["count"]
    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, result["timestamp"])
  end

  def test_collection_response_with_string_name
    items = [ { "id" => 1 } ]
    result = @formatter.collection_response(items, "tables")

    assert_equal items, result["tables"]
    assert_equal 1, result["count"]
  end

  def test_collection_response_with_metadata
    items = [ { "id" => 1 }, { "id" => 2 } ]
    result = @formatter.collection_response(
      items,
      :members,
      total_count: 100,
      filtered: true,
      query: "test"
    )

    assert_equal items, result["members"]
    assert_equal 2, result["count"]
    assert_equal 100, result["total_count"]
    assert_equal true, result["filtered"]
    assert_equal "test", result["query"]
  end

  def test_collection_response_empty
    result = @formatter.collection_response([], :solutions)

    assert_equal [], result["solutions"]
    assert_equal 0, result["count"]
  end

  def test_collection_response_with_symbol_metadata
    items = [ 1, 2, 3 ]
    result = @formatter.collection_response(items, :data, cached: true)

    assert_equal true, result["cached"]
  end

  # Test timestamp format consistency
  def test_timestamps_are_iso8601_utc
    operation = @formatter.operation_response("test", "message")
    error = @formatter.error_response("test", "message")
    query = @formatter.query_response
    collection = @formatter.collection_response([], :test)

    [ operation, error, query, collection ].each do |response|
      timestamp = response["timestamp"]
      assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, timestamp)

      # Verify it's valid ISO 8601
      parsed = Time.parse(timestamp)
      assert parsed.utc?
    end
  end

  # Test that responses are plain hashes (no frozen strings, etc.)
  def test_responses_are_mutable_hashes
    result = @formatter.operation_response("test", "message", data: "value")

    assert result.is_a?(Hash)
    refute result.frozen?

    # Should be able to modify
    result["new_key"] = "new_value"
    assert_equal "new_value", result["new_key"]
  end

  # Test key transformation
  def test_symbol_keys_transformed_to_strings
    result = @formatter.operation_response("test", "msg", symbol_key: "value")

    assert result.key?("symbol_key")
    refute result.key?(:symbol_key)
  end

  # Edge cases
  def test_operation_response_with_nil_data_values
    result = @formatter.operation_response("test", "msg", value: nil, count: 0)

    assert_nil result["value"]
    assert_equal 0, result["count"]
  end

  def test_error_response_with_empty_message
    result = @formatter.error_response("test_error", "")

    assert_equal "", result["message"]
    assert result.key?("message")
  end

  def test_collection_response_preserves_item_structure
    items = [
      { "id" => 1, "nested" => { "a" => "b" } },
      { "id" => 2, "array" => [ 1, 2, 3 ] }
    ]
    result = @formatter.collection_response(items, :data)

    assert_equal items, result["data"]
    assert_equal({ "a" => "b" }, result["data"][0]["nested"])
    assert_equal([ 1, 2, 3 ], result["data"][1]["array"])
  end
end
