# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative 'paths'

module SmartSuite
  # Unified logging system for SmartSuite MCP server.
  #
  # Consolidates all logging into a single configurable class with:
  # - Multiple log levels (DEBUG, INFO, WARN, ERROR)
  # - Multiple output destinations (file, stderr)
  # - Log categories (API, DB, CACHE, S3, SERVER, METRIC)
  # - ANSI color support (configurable)
  # - Daily log rotation
  # - Test mode support via SmartSuite::Paths
  #
  # @example Basic usage
  #   SmartSuite::Logger.info('Server started')
  #   SmartSuite::Logger.api('GET /solutions/', status: 200, duration: 0.5)
  #   SmartSuite::Logger.cache('hit', table_id: 'tbl_123')
  #
  # @example Configure log level
  #   SmartSuite::Logger.level = :warn  # Only warnings and errors
  #
  # @example Disable colors
  #   SmartSuite::Logger.colors_enabled = false
  #
  class Logger
    # Log levels in order of verbosity
    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }.freeze

    # Log categories with their associated colors
    CATEGORIES = {
      api: { color: "\e[36m", prefix: 'API' },       # Cyan
      db: { color: "\e[32m", prefix: 'DB' },         # Green
      cache: { color: "\e[35m", prefix: 'CACHE' },   # Magenta
      s3: { color: "\e[34m", prefix: 'S3' },         # Blue
      server: { color: "\e[37m", prefix: 'SERVER' }, # White
      metric: { color: "\e[33m", prefix: '📊' } # Yellow
    }.freeze

    # ANSI codes
    RESET = "\e[0m"
    RED = "\e[31m"
    GREEN = "\e[32m"
    YELLOW = "\e[33m"

    class << self
      # Get/set the current log level
      # @return [Symbol] current log level (:debug, :info, :warn, :error)
      attr_writer :level

      # Get/set whether colors are enabled
      # @return [Boolean] true if ANSI colors are enabled
      attr_writer :colors_enabled

      # Get/set whether to output to stderr
      # @return [Boolean] true if stderr output is enabled
      attr_writer :stderr_enabled

      def level
        @level ||= (ENV['SMARTSUITE_LOG_LEVEL'] || 'debug').downcase.to_sym
      end

      def colors_enabled
        @colors_enabled = true if @colors_enabled.nil?
        @colors_enabled
      end

      def stderr_enabled
        @stderr_enabled = ENV['SMARTSUITE_LOG_STDERR'] == 'true' if @stderr_enabled.nil?
        @stderr_enabled
      end

      # Get the unified log file path
      #
      # @return [String] absolute path to log file
      def log_file_path
        if integration_test_environment?
          File.expand_path('~/.smartsuite_mcp_integration.log')
        elsif test_environment?
          File.expand_path('~/.smartsuite_mcp_test.log')
        else
          File.expand_path('~/.smartsuite_mcp.log')
        end
      end

      # Detect if running in integration test environment
      # @return [Boolean]
      def integration_test_environment?
        caller_locations.any? { |loc| loc.path.include?('test/integration/') }
      end

      # Detect if running in test environment
      # @return [Boolean]
      def test_environment?
        SmartSuite::Paths.test_mode? ||
          ENV['RACK_ENV'] == 'test' ||
          ENV['RAILS_ENV'] == 'test' ||
          defined?(Minitest) ||
          defined?(RSpec)
      end

      # Get the shared Logger instance
      # @return [::Logger] configured logger instance
      def file_logger
        @file_logger ||= begin
          log_path = log_file_path
          FileUtils.mkdir_p(File.dirname(log_path))
          logger = ::Logger.new(log_path, 'daily')
          logger.level = ::Logger::DEBUG
          logger.formatter = proc do |severity, datetime, _progname, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} #{msg}\n"
          end
          logger
        end
      end

      # Reset the logger instance (useful for tests)
      def reset!
        @file_logger&.close
        @file_logger = nil
        @level = nil
        @colors_enabled = nil
        @stderr_enabled = nil
      end

      # Check if a message at the given level should be logged
      # @param msg_level [Symbol] the level of the message
      # @return [Boolean]
      def should_log?(msg_level)
        LEVELS[msg_level] >= LEVELS[level]
      end

      # === Generic logging methods ===

      # Log a debug message
      # @param message [String] message to log
      # @param category [Symbol] optional category
      def debug(message, category: nil)
        log(:debug, message, category: category)
      end

      # Log an info message
      # @param message [String] message to log
      # @param category [Symbol] optional category
      def info(message, category: nil)
        log(:info, message, category: category)
      end

      # Log a warning message
      # @param message [String] message to log
      # @param category [Symbol] optional category
      def warn(message, category: nil)
        log(:warn, message, category: category)
      end

      # Log an error message
      # @param message [String] message to log
      # @param error [Exception] optional exception
      # @param category [Symbol] optional category
      def error(message, error: nil, category: nil)
        full_message = message
        if error
          full_message += " | #{error.class}: #{error.message}"
          full_message += "\n#{error.backtrace.first(5).join("\n")}" if error.backtrace
        end
        log(:error, full_message, category: category)
      end

      # === Category-specific logging methods ===

      # Log API request
      # @param method [Symbol] HTTP method
      # @param url [String] request URL
      # @param params [Hash] optional parameters (query_params, body)
      def api_request(method, url, params = {})
        return unless should_log?(:info)

        query_params = params[:query_params] || {}
        body = params[:body]

        msg = "→ #{method.to_s.upcase} #{url}"
        msg += " | Query: #{query_params.inspect}" unless query_params.empty?
        msg += " | Body: #{truncate_json(body)}" if body

        log(:info, msg, category: :api)
      end

      # Log API response
      # @param status [Integer] HTTP status code
      # @param duration [Float] request duration in seconds
      # @param body_size [Integer] response body size in bytes
      def api_response(status, duration, body_size = nil)
        return unless should_log?(:info)

        success = status >= 200 && status < 300
        msg = "← #{status} | #{format_duration(duration)}"
        msg += " | #{format_bytes(body_size)}" if body_size

        log(:info, msg, category: :api, success: success)
      end

      # Log database query
      # @param sql [String] SQL query
      # @param params [Array] query parameters
      # @param duration [Float] query duration in seconds
      def db_query(sql, params = [], duration = nil)
        return unless should_log?(:debug)

        clean_sql = sql.gsub(/\s+/, ' ').strip
        msg = "→ #{clean_sql}"
        msg += " | Params: #{params.inspect}" unless params.empty?
        msg += " | #{format_duration(duration)}" if duration

        log(:debug, msg, category: :db)
      end

      # Log database result
      # @param row_count [Integer] number of rows returned
      # @param duration [Float] query duration in seconds
      def db_result(row_count, duration = nil)
        return unless should_log?(:debug)

        msg = "← #{row_count} rows"
        msg += " | #{format_duration(duration)}" if duration

        log(:debug, msg, category: :db)
      end

      # Log cache operation
      # @param operation [String] operation type (hit, miss, invalidate, etc.)
      # @param table_id [String] table identifier
      # @param details [Hash] additional details
      def cache(operation, table_id, details = {})
        return unless should_log?(:info)

        msg = "#{operation.upcase} | Table: #{table_id}"
        details.each { |k, v| msg += " | #{k}: #{v}" }

        log(:info, msg, category: :cache)
      end

      # Log cache query
      # @param table_id [String] table identifier
      # @param filters [Hash] filter criteria
      # @param limit [Integer] limit
      # @param offset [Integer] offset
      def cache_query(table_id, filters = {}, limit: nil, offset: nil)
        return unless should_log?(:info)

        msg = "QUERY | Table: #{table_id}"
        msg += " | Filters: #{filters.inspect}" unless filters.empty?
        msg += " | Limit: #{limit}" if limit
        msg += " | Offset: #{offset}" if offset

        log(:info, msg, category: :cache)
      end

      # Log S3 operation
      # @param action [String] action type (UPLOAD, DELETE, etc.)
      # @param message [String] details
      def s3(action, message)
        return unless should_log?(:info)

        log(:info, "#{action.upcase} | #{message}", category: :s3)
      end

      # Log server event
      # @param message [String] message to log
      def server(message)
        return unless should_log?(:info)

        log(:info, message, category: :server)
      end

      # Log metric (tool calls, token usage)
      # @param message [String] message to log
      def metric(message)
        return unless should_log?(:info)

        log(:info, message, category: :metric)
      end

      # Log a separator line
      # @param char [String] character to use for the line
      # @param length [Integer] line length
      def separator(char = '=', length = 50)
        return unless should_log?(:info)

        log(:info, char * length, category: :metric)
      end

      private

      # Core logging method
      # @param level [Symbol] log level
      # @param message [String] message to log
      # @param category [Symbol] optional category
      # @param success [Boolean] for success/failure coloring
      def log(level, message, category: nil, success: nil)
        return unless should_log?(level)

        formatted = format_message(message, category: category, success: success)

        # Log to file (without colors)
        file_logger.send(level, strip_colors(formatted))

        # Optionally log to stderr (with colors if enabled)
        return unless stderr_enabled

        warn "[#{Time.now.strftime('%H:%M:%S')}] #{formatted}"
      end

      # Format message with category prefix and colors
      def format_message(message, category: nil, success: nil)
        return message unless category

        cat_config = CATEGORIES[category]
        return message unless cat_config

        prefix = cat_config[:prefix]
        color = cat_config[:color]

        # Override color for success/failure
        unless success.nil?
          color = success ? GREEN : RED
        end

        if colors_enabled
          "#{color}#{prefix.ljust(6)} #{message}#{RESET}"
        else
          "#{prefix.ljust(6)} #{message}"
        end
      end

      # Strip ANSI color codes from string
      def strip_colors(str)
        str.gsub(/\e\[[0-9;]*m/, '')
      end

      # Truncate JSON for logging
      def truncate_json(obj, max_length = 200)
        return nil if obj.nil?

        json = obj.is_a?(String) ? obj : obj.to_json
        json.length > max_length ? "#{json[0...max_length]}... (#{json.length} bytes)" : json
      end

      # Format duration in milliseconds
      def format_duration(seconds)
        return nil if seconds.nil?

        "#{(seconds * 1000).round(1)}ms"
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
end
