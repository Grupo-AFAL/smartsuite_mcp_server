require 'json'
require 'net/http'
require 'uri'
require 'openssl'
require_relative '../../query_logger'

module SmartSuite
  module API
    # HttpClient handles all HTTP communication with the SmartSuite API.
    #
    # This module provides:
    # - HTTP request execution (GET, POST, PUT, PATCH, DELETE)
    # - Authentication header management
    # - Error handling for failed requests
    # - Metrics logging for all API calls
    # - Token usage tracking
    # - Query logging for debugging
    module HttpClient
      # Base URL for all SmartSuite API requests
      API_BASE_URL = 'https://app.smartsuite.com/api/v1'

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

        log_metric("→ #{method.upcase} #{endpoint}")

        uri = URI.parse("#{API_BASE_URL}#{endpoint}")

        # Log API request
        QueryLogger.log_api_request(method, uri.to_s, body: body)

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

        request['Authorization'] = "Token #{@api_key}"
        request['Account-Id'] = @account_id
        request['Content-Type'] = 'application/json'

        if body
          request.body = JSON.generate(body)
        end

        response = http.request(request)

        duration = Time.now - start_time

        unless response.is_a?(Net::HTTPSuccess)
          QueryLogger.log_api_response(response.code.to_i, duration, response.body&.length)
          raise "API request failed: #{response.code} - #{response.body}"
        end

        # Log successful response
        body_size = response.body&.length
        QueryLogger.log_api_response(response.code.to_i, duration, body_size)

        # Handle empty responses (some endpoints return empty body on success)
        return {} if response.body.nil? || response.body.strip.empty?

        JSON.parse(response.body)
      rescue StandardError => e
        QueryLogger.log_error("API Request", e)
        raise
      end

      # Logs a message to the metrics log file with timestamp.
      #
      # @param message [String] Message to log
      def log_metric(message)
        timestamp = Time.now.strftime('%H:%M:%S')
        @metrics_log.puts "[#{timestamp}] #{message}"
      end

      # Logs token usage and updates running totals.
      #
      # Tracks cumulative token usage and calculates remaining context window.
      #
      # @param tokens_used [Integer] Number of tokens used in this operation
      def log_token_usage(tokens_used)
        @total_tokens_used += tokens_used
        remaining = @context_limit - @total_tokens_used
        log_metric("📊 Tokens: +#{tokens_used} | Total: #{@total_tokens_used} | Remaining: #{remaining}")
      end
    end
  end
end
