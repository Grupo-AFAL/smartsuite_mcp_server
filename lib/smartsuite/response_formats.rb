# frozen_string_literal: true

require 'time'

module SmartSuite
  # ResponseFormats provides standardized response building for MCP tools.
  #
  # This module ensures consistent response structures across all operations including:
  # - Standardized timestamp fields (ISO 8601 UTC)
  # - Consistent status indicators
  # - Structured error responses  # - Collection response wrappers
  #
  # All MCP tool responses should use these builders for consistency.
  #
  # @example Operation response
  #   operation_response('refresh', 'Cache invalidated', refreshed: 'solutions')
  #
  # @example Error response
  #   error_response('cache_disabled', 'Cache is not enabled')
  #
  # @example Query response
  #   query_response(solutions: [...], tables: [...])
  module ResponseFormats
    # Build a standardized operation response (for mutations/actions).
    #
    # Use this for operations that perform actions like refresh, warm, reset, analyze.
    # Always includes status, operation, message, and timestamp fields.
    #
    # @param operation [String] Operation identifier (e.g., 'refresh', 'warm', 'reset', 'analyze')
    # @param message [String] Human-readable description of what happened
    # @param status [String] Operation status: 'success', 'completed', 'no_action', 'partial' (default: 'success')
    # @param data [Hash] Additional operation-specific data to merge
    # @return [Hash] Standardized operation response
    # @example Basic operation
    #   operation_response('refresh', 'Cache invalidated')
    #   # => {"status" => "success", "operation" => "refresh", "message" => "...", "timestamp" => "..."}
    #
    # @example With additional data
    #   operation_response('warm', 'Warmed 3 tables', status: 'completed', data: {warmed: 3, skipped: 2})
    #   # => {"status" => "completed", "operation" => "warm", "message" => "...", "warmed" => 3, ...}
    def operation_response(operation, message, status: 'success', **data)
      {
        'status' => status,
        'operation' => operation,
        'message' => message,
        'timestamp' => Time.now.utc.iso8601
      }.merge(data.transform_keys(&:to_s))
    end

    # Build a standardized error response.
    #
    # Use this for any error condition. Provides consistent structure for error handling.
    # Always includes status='error', error code, message, and timestamp.
    #
    # @param error [String] Short error identifier (e.g., 'cache_disabled', 'invalid_parameter')
    # @param message [String] Detailed error message for users
    # @param data [Hash] Additional error context (optional)
    # @return [Hash] Standardized error response
    # @example Simple error
    #   error_response('cache_disabled', 'Cache is not enabled')
    #   # => {"status" => "error", "error" => "cache_disabled", "message" => "...", "timestamp" => "..."}
    #
    # @example With context
    #   error_response('invalid_parameter', 'table_id is required', parameter: 'table_id')
    def error_response(error, message, **data)
      {
        'status' => 'error',
        'error' => error,
        'message' => message,
        'timestamp' => Time.now.utc.iso8601
      }.merge(data.transform_keys(&:to_s))
    end

    # Build a standardized query response (for read operations).
    #
    # Use this for queries that return data without performing actions.
    # Always includes timestamp and merges in the query results.
    #
    # @param data [Hash] Query results as key-value pairs
    # @return [Hash] Standardized query response with timestamp
    # @example Cache status query
    #   query_response(solutions: {...}, tables: {...}, records: [...])
    #   # => {"timestamp" => "...", "solutions" => {...}, "tables" => {...}, ...}
    #
    # @example Stats query
    #   query_response(time_range: 'all', summary: {...}, by_method: {...})
    def query_response(**data)
      {
        'timestamp' => Time.now.utc.iso8601
      }.merge(data.transform_keys(&:to_s))
    end

    # Build a standardized collection response.
    #
    # Wrapper around Base#build_collection_response that adds timestamp.
    # Use this for list operations that return arrays of items.
    #
    # @param items [Array] Collection items
    # @param collection_name [String, Symbol] Key name for the collection
    # @param metadata [Hash] Additional metadata (count added automatically)
    # @return [Hash] Standardized collection response
    # @example List solutions
    #   collection_response(solutions, :solutions)
    #   # => {"solutions" => [...], "count" => 10, "timestamp" => "..."}
    #
    # @example With metadata
    #   collection_response(members, :members, total_count: 100, filtered: true)
    def collection_response(items, collection_name, **metadata)
      {
        collection_name.to_s => items,
        'count' => items.size,
        'timestamp' => Time.now.utc.iso8601
      }.merge(metadata.transform_keys(&:to_s))
    end
  end
end
