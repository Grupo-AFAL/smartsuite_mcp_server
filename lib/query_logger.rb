# frozen_string_literal: true

require 'logger'
require 'fileutils'

# QueryLogger provides centralized logging for all API and database queries.
# Logs to ~/.smartsuite_mcp_queries.log for easy debugging and monitoring.
#
# Usage:
#   QueryLogger.log_api_request(method, url, params)
#   QueryLogger.log_api_response(status, duration, body_size)
#   QueryLogger.log_db_query(sql, params, duration)
#   QueryLogger.log_cache_operation(operation, table_id, details)
#
# Tail the log:
#   tail -f ~/.smartsuite_mcp_queries.log
#   tail -f ~/.smartsuite_mcp_queries.log | grep "API"
#   tail -f ~/.smartsuite_mcp_queries.log | grep "DB"
#
class QueryLogger
  LOG_FILE = File.expand_path('~/.smartsuite_mcp_queries.log')

  class << self
    def logger
      @logger ||= begin
        FileUtils.mkdir_p(File.dirname(LOG_FILE))
        logger = Logger.new(LOG_FILE, 'daily')
        logger.level = Logger::DEBUG
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} #{msg}\n"
        end
        logger
      end
    end

    # Log API request to SmartSuite
    # @param method [Symbol] HTTP method (:get, :post, :put, :patch, :delete)
    # @param url [String] Full URL or endpoint path
    # @param params [Hash] Query parameters and/or body
    def log_api_request(method, url, params = {})
      query_params = params[:query_params] || {}
      body = params[:body]

      msg = "API → #{method.to_s.upcase} #{url}"
      msg += " | Query: #{query_params.inspect}" unless query_params.empty?
      msg += " | Body: #{truncate_json(body)}" if body

      logger.info(msg)
    end

    # Log API response
    # @param status [Integer] HTTP status code
    # @param duration [Float] Request duration in seconds
    # @param body_size [Integer] Response body size in bytes (optional)
    def log_api_response(status, duration, body_size = nil)
      msg = "API ← #{status} | #{(duration * 1000).round(1)}ms"
      msg += " | #{format_bytes(body_size)}" if body_size

      logger.info(msg)
    end

    # Log database query
    # @param sql [String] SQL query
    # @param params [Array] Query parameters
    # @param duration [Float] Query duration in seconds (optional)
    def log_db_query(sql, params = [], duration = nil)
      # Clean up SQL for readability
      clean_sql = sql.gsub(/\s+/, ' ').strip

      msg = "DB  → #{clean_sql}"
      msg += " | Params: #{params.inspect}" unless params.empty?
      msg += " | #{(duration * 1000).round(1)}ms" if duration

      logger.debug(msg)
    end

    # Log database query result
    # @param row_count [Integer] Number of rows returned
    # @param duration [Float] Query duration in seconds (optional)
    def log_db_result(row_count, duration = nil)
      msg = "DB  ← #{row_count} rows"
      msg += " | #{(duration * 1000).round(1)}ms" if duration

      logger.debug(msg)
    end

    # Log cache operation
    # @param operation [String] Operation type (hit, miss, fetch, invalidate, etc.)
    # @param table_id [String] Table ID
    # @param details [Hash] Additional details
    def log_cache_operation(operation, table_id, details = {})
      msg = "CACHE #{operation.upcase} | Table: #{table_id}"
      details.each { |k, v| msg += " | #{k}: #{v}" }

      logger.info(msg)
    end

    # Log cache query building
    # @param table_id [String] Table ID
    # @param filters [Hash] Filter criteria
    # @param limit [Integer] Limit
    # @param offset [Integer] Offset
    def log_cache_query(table_id, filters = {}, limit: nil, offset: nil)
      msg = "CACHE QUERY | Table: #{table_id}"
      msg += " | Filters: #{filters.inspect}" unless filters.empty?
      msg += " | Limit: #{limit}" if limit
      msg += " | Offset: #{offset}" if offset

      logger.info(msg)
    end

    # Log error
    # @param context [String] Context where error occurred
    # @param error [Exception] The error
    def log_error(context, error)
      logger.error("#{context} | ERROR: #{error.class}: #{error.message}")
      logger.error(error.backtrace.first(5).join("\n")) if error.backtrace
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
