# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "openssl"
require_relative "../logger"

# SmartSuite namespace module
#
# Top-level module for all SmartSuite MCP server components.
# Contains API client, cache layer, formatters, and MCP protocol modules.
module SmartSuite
  # API operations module
  #
  # Contains all modules for interacting with the SmartSuite API.
  # Includes HTTP client, workspace operations, table operations, record operations,
  # field operations, member operations, comment operations, and view operations.
  module API
    # HttpClient handles all HTTP communication with the SmartSuite API.
    #
    # This module provides:
    # - HTTP request execution (GET, POST, PUT, PATCH, DELETE)
    # - Authentication header management
    # - Error handling for failed requests
    # - Unified logging for all API calls
    # - Token usage tracking
    module HttpClient
      # Base URL for all SmartSuite API requests
      API_BASE_URL = "https://app.smartsuite.com/api/v1"

      # Executes an HTTP request to the SmartSuite API.
      #
      # Handles authentication, request serialization, response parsing, and error handling.
      # Automatically tracks API calls for statistics and logs metrics.
      #
      # @param method [Symbol] HTTP method (:get, :post, :put, :patch, :delete)
      # @param endpoint [String] API endpoint path (e.g., '/solutions/')
      # @param body [Hash, nil] Optional request body (will be JSON-encoded)
      # @return [Hash] Parsed JSON response from API
      # @raise [RuntimeError] If API returns non-2xx status code
      def api_request(method, endpoint, body = nil)
        # Track the API call if stats tracker is available
        @stats_tracker&.track_api_call(method, endpoint)

        uri = URI.parse("#{API_BASE_URL}#{endpoint}")

        # Log API request
        SmartSuite::Logger.api_request(method, uri.to_s, body: body)

        start_time = Time.now

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        request = case method
        when :get
                    Net::HTTP::Get.new(uri.request_uri)
        when :post
                    Net::HTTP::Post.new(uri.request_uri)
        when :put
                    Net::HTTP::Put.new(uri.request_uri)
        when :patch
                    Net::HTTP::Patch.new(uri.request_uri)
        when :delete
                    Net::HTTP::Delete.new(uri.request_uri)
        end

        request["Authorization"] = "Token #{@api_key}"
        request["Account-Id"] = @account_id
        request["Content-Type"] = "application/json"

        request.body = JSON.generate(body) if body

        response = http.request(request)

        duration = Time.now - start_time

        unless response.is_a?(Net::HTTPSuccess)
          SmartSuite::Logger.api_response(response.code.to_i, duration, response.body&.length)
          error_message = format_api_error(response.code.to_i, response.body, endpoint)
          raise error_message
        end

        # Log successful response
        body_size = response.body&.length
        SmartSuite::Logger.api_response(response.code.to_i, duration, body_size)

        # Handle empty responses (some endpoints return empty body on success)
        return {} if response.body.nil? || response.body.strip.empty?

        JSON.parse(response.body)
      rescue StandardError => e
        SmartSuite::Logger.error("API Request", error: e)
        raise
      end

      # Formats API error messages to be more helpful for AI assistants.
      #
      # Parses SmartSuite error responses and provides actionable guidance.
      #
      # @param status_code [Integer] HTTP status code
      # @param body [String] Response body (JSON)
      # @param endpoint [String] API endpoint that failed
      # @return [String] Formatted error message with guidance
      def format_api_error(status_code, body, endpoint)
        parsed = JSON.parse(body) rescue nil

        base_message = "API request failed (#{status_code})"

        if parsed.is_a?(Hash)
          # Extract field-specific errors
          errors = extract_field_errors(parsed)
          if errors.any?
            return "#{base_message}: #{errors.join('; ')}. Check the field data and try again."
          end

          # Handle common error patterns
          if parsed["detail"]
            return "#{base_message}: #{parsed['detail']}"
          end

          if parsed["error"]
            return "#{base_message}: #{parsed['error']}"
          end

          if parsed["message"]
            return "#{base_message}: #{parsed['message']}"
          end
        end

        # Fallback to raw response
        "#{base_message}: #{body}"
      end

      # Extracts field-specific errors from SmartSuite error response.
      #
      # @param parsed [Hash] Parsed error response
      # @return [Array<String>] List of error messages
      def extract_field_errors(parsed)
        errors = []

        parsed.each do |key, value|
          if value.is_a?(Hash)
            value.each do |field, messages|
              if messages.is_a?(Array)
                errors << "#{key}.#{field}: #{messages.join(', ')}"
              else
                errors << "#{key}.#{field}: #{messages}"
              end
            end
          elsif value.is_a?(Array)
            errors << "#{key}: #{value.join(', ')}"
          end
        end

        errors
      end

      # Logs a metric message to the unified logger.
      #
      # This method provides backward compatibility for all API modules
      # that use log_metric for status messages.
      #
      # @param message [String] Message to log
      def log_metric(message)
        SmartSuite::Logger.metric(message)
      end

      # Updates token usage totals and returns the new total.
      #
      # Tracks cumulative token usage. Does not log - caller handles logging.
      #
      # @param tokens_used [Integer] Number of tokens used in this operation
      # @return [Integer] New total tokens used
      def update_token_usage(tokens_used)
        @total_tokens_used += tokens_used
        @total_tokens_used
      end
    end
  end
end
