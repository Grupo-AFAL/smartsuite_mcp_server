# frozen_string_literal: true

require 'logger'
require 'fileutils'

# QueryLogger provides centralized logging for all API and database queries.
#
# Logs to separate files based on environment:
# - Production: ~/.smartsuite_mcp_queries.log
# - Unit tests: ~/.smartsuite_mcp_queries_test.log
# - Integration tests: ~/.smartsuite_mcp_queries_integration.log
#
# Usage:
#   QueryLogger.log_api_request(method, url, params)
#   QueryLogger.log_api_response(status, duration, body_size)
#   QueryLogger.log_db_query(sql, params, duration)
#   QueryLogger.log_cache_operation(operation, table_id, details)
#
# Tail the production log:
#   tail -f ~/.smartsuite_mcp_queries.log
#   tail -f ~/.smartsuite_mcp_queries.log | grep "API"
#   tail -f ~/.smartsuite_mcp_queries.log | grep "DB"
#
# Tail the unit test log:
#   tail -f ~/.smartsuite_mcp_queries_test.log
#
# Tail the integration test log:
#   tail -f ~/.smartsuite_mcp_queries_integration.log
#
class QueryLogger
  # ANSI color codes for terminal output
  COLORS = {
    reset: "\e[0m",
    api: "\e[36m",      # Cyan for API calls
    db: "\e[32m",       # Green for database queries
    cache: "\e[35m",    # Magenta for cache operations
    s3: "\e[34m",       # Blue for S3 operations
    error: "\e[31m",    # Red for errors
    success: "\e[32m",  # Green for success
    warning: "\e[33m"   # Yellow for warnings
  }.freeze

  class << self
    # Get the log file path based on environment
    #
    # Returns different paths for integration tests, unit tests, and production:
    # - Integration tests: ~/.smartsuite_mcp_queries_integration.log
    # - Unit tests: ~/.smartsuite_mcp_queries_test.log
    # - Production: ~/.smartsuite_mcp_queries.log
    #
    # @return [String] absolute path to log file
    def log_file_path
      if integration_test_environment?
        File.expand_path('~/.smartsuite_mcp_queries_integration.log')
      elsif test_environment?
        File.expand_path('~/.smartsuite_mcp_queries_test.log')
      else
        File.expand_path('~/.smartsuite_mcp_queries.log')
      end
    end

    # Detect if running in integration test environment
    #
    # Integration tests use real API credentials and run against a test workspace.
    # We detect them by checking if we're in the test/integration directory context.
    #
    # @return [Boolean] true if in integration test environment
    def integration_test_environment?
      # Check if called from integration test file
      caller_locations.any? { |loc| loc.path.include?('test/integration/') }
    end

    # Detect if running in test environment
    #
    # Checks for common test indicators:
    # - RACK_ENV or RAILS_ENV set to 'test'
    # - Running under minitest or rspec
    #
    # @return [Boolean] true if in test environment
    def test_environment?
      ENV['RACK_ENV'] == 'test' ||
        ENV['RAILS_ENV'] == 'test' ||
        defined?(Minitest) ||
        defined?(RSpec)
    end

    # Get the shared Logger instance
    #
    # Creates a daily rotating logger if not already initialized.
    # Logs to different files based on environment (test vs production).
    #
    # @return [Logger] configured logger instance
    def logger
      @logger ||= begin
        log_path = log_file_path
        FileUtils.mkdir_p(File.dirname(log_path))
        logger = Logger.new(log_path, 'daily')
        logger.level = Logger::DEBUG
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} #{msg}\n"
        end
        logger
      end
    end

    # Reset the logger instance (useful for switching environments in tests)
    def reset_logger!
      @logger&.close
      @logger = nil
    end

    # Log API request to SmartSuite
    # @param method [Symbol] HTTP method (:get, :post, :put, :patch, :delete)
    # @param url [String] Full URL or endpoint path
    # @param params [Hash] Query parameters and/or body
    def log_api_request(method, url, params = {})
      query_params = params[:query_params] || {}
      body = params[:body]

      msg = "#{COLORS[:api]}API → #{method.to_s.upcase} #{url}"
      msg += " | Query: #{query_params.inspect}" unless query_params.empty?
      msg += " | Body: #{truncate_json(body)}" if body
      msg += COLORS[:reset]

      logger.info(msg)
    end

    # Log API response
    # @param status [Integer] HTTP status code
    # @param duration [Float] Request duration in seconds
    # @param body_size [Integer] Response body size in bytes (optional)
    def log_api_response(status, duration, body_size = nil)
      color = status >= 200 && status < 300 ? COLORS[:success] : COLORS[:error]
      msg = "#{color}API ← #{status} | #{(duration * 1000).round(1)}ms"
      msg += " | #{format_bytes(body_size)}" if body_size
      msg += COLORS[:reset]

      logger.info(msg)
    end

    # Log database query
    # @param sql [String] SQL query
    # @param params [Array] Query parameters
    # @param duration [Float] Query duration in seconds (optional)
    def log_db_query(sql, params = [], duration = nil)
      # Clean up SQL for readability
      clean_sql = sql.gsub(/\s+/, ' ').strip

      msg = "#{COLORS[:db]}DB  → #{clean_sql}"
      msg += " | Params: #{params.inspect}" unless params.empty?
      msg += " | #{(duration * 1000).round(1)}ms" if duration
      msg += COLORS[:reset]

      logger.debug(msg)
    end

    # Log database query result
    # @param row_count [Integer] Number of rows returned
    # @param duration [Float] Query duration in seconds (optional)
    def log_db_result(row_count, duration = nil)
      msg = "#{COLORS[:db]}DB  ← #{row_count} rows"
      msg += " | #{(duration * 1000).round(1)}ms" if duration
      msg += COLORS[:reset]

      logger.debug(msg)
    end

    # Log cache operation
    # @param operation [String] Operation type (hit, miss, fetch, invalidate, etc.)
    # @param table_id [String] Table ID
    # @param details [Hash] Additional details
    def log_cache_operation(operation, table_id, details = {})
      msg = "#{COLORS[:cache]}CACHE #{operation.upcase} | Table: #{table_id}"
      details.each { |k, v| msg += " | #{k}: #{v}" }
      msg += COLORS[:reset]

      logger.info(msg)
    end

    # Log cache query building
    # @param table_id [String] Table ID
    # @param filters [Hash] Filter criteria
    # @param limit [Integer] Limit
    # @param offset [Integer] Offset
    def log_cache_query(table_id, filters = {}, limit: nil, offset: nil)
      msg = "#{COLORS[:cache]}CACHE QUERY | Table: #{table_id}"
      msg += " | Filters: #{filters.inspect}" unless filters.empty?
      msg += " | Limit: #{limit}" if limit
      msg += " | Offset: #{offset}" if offset
      msg += COLORS[:reset]

      logger.info(msg)
    end

    # Log S3 operation
    # @param action [String] Action type (UPLOAD, DELETE, PRESIGN, etc.)
    # @param message [String] Details about the operation
    def log_s3_operation(action, message)
      msg = "#{COLORS[:s3]}S3 #{action.upcase} | #{message}#{COLORS[:reset]}"
      logger.info(msg)
    end

    # Log error
    # @param context [String] Context where error occurred
    # @param error [Exception] The error
    def log_error(context, error)
      logger.error("#{COLORS[:error]}#{context} | ERROR: #{error.class}: #{error.message}#{COLORS[:reset]}")
      logger.error("#{COLORS[:error]}#{error.backtrace.first(5).join("\n")}#{COLORS[:reset]}") if error.backtrace
    end

    private

    # Truncate JSON for logging
    def truncate_json(obj, max_length = 200)
      return nil if obj.nil?

      json = obj.is_a?(String) ? obj : obj.to_json
      json.length > max_length ? "#{json[0...max_length]}... (#{json.length} bytes)" : json
    end

    # Format bytes for human readability
    def format_bytes(bytes)
      return nil if bytes.nil?

      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / (1024.0 * 1024)).round(1)}MB"
      end
    end
  end
end
