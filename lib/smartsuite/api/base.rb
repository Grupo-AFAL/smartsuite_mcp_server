# frozen_string_literal: true

require 'uri'

module SmartSuite
  module API
    # Base module providing common functionality for all API operation modules.
    #
    # This module extracts shared patterns across WorkspaceOperations, TableOperations,
    # RecordOperations, FieldOperations, MemberOperations, CommentOperations, and ViewOperations.
    #
    # Key features:
    # - Parameter validation with helpful error messages
    # - Query parameter building with proper URL encoding
    # - Cache coordination patterns
    # - Response tracking and token logging
    # - Pagination constants
    #
    # Include this module in all API operation modules to access shared helpers.
    #
    # @example
    #   module SmartSuite::API::WorkspaceOperations
    #     include SmartSuite::API::Base
    #
    #     def list_solutions
    #       validate_optional_parameter!('fields', fields, Array)
    #       endpoint = build_endpoint('/solutions/', fields: fields)
    #       response = api_request(:get, endpoint)
    #       track_response_size(response, "Found #{response['items'].size} solutions")
    #     end
    #   end
    module Base
      # Pagination defaults used across all API modules
      module Pagination
        # Default limit for list operations when not specified
        DEFAULT_LIMIT = 100

        # Batch size for fetch_all operations (maximize API efficiency)
        FETCH_ALL_LIMIT = 1000

        # Maximum allowed limit (SmartSuite API restriction)
        MAX_LIMIT = 1000

        # Default offset for pagination
        DEFAULT_OFFSET = 0
      end

      # Validate that a required parameter is present and non-empty.
      #
      # Raises ArgumentError with a helpful message if validation fails.
      #
      # @param name [String] Parameter name for error message
      # @param value [Object] Parameter value to validate
      # @param type [Class, nil] Optional type constraint
      # @raise [ArgumentError] if value is nil, empty, or wrong type
      # @example
      #   validate_required_parameter!('table_id', table_id)
      #   validate_required_parameter!('fields', fields, Array)
      def validate_required_parameter!(name, value, type = nil)
        raise ArgumentError, "#{name} is required and cannot be nil or empty" if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        raise ArgumentError, "#{name} must be a #{type}, got #{value.class}" if type && !value.is_a?(type)

        value
      end

      # Validate that an optional parameter (if provided) is the correct type.
      #
      # Does not raise error if value is nil, but validates type if present.
      #
      # @param name [String] Parameter name for error message
      # @param value [Object] Parameter value to validate
      # @param type [Class] Expected type
      # @raise [ArgumentError] if value is present but wrong type
      # @example
      #   validate_optional_parameter!('fields', fields, Array)
      def validate_optional_parameter!(name, value, type)
        return if value.nil?

        raise ArgumentError, "#{name} must be a #{type}, got #{value.class}" unless value.is_a?(type)

        value
      end

      # Build API endpoint URL with query parameters.
      #
      # Handles array parameters (repeats key), proper URL encoding, and empty parameter filtering.
      # Supports all SmartSuite API query parameter patterns.
      #
      # @param path [String] Base endpoint path (e.g., '/solutions/')
      # @param params [Hash] Query parameters as key-value pairs
      # @return [String] Complete endpoint with query string
      # @example Single value parameters
      #   build_endpoint('/solutions/', limit: 100, offset: 0)
      #   #=> "/solutions/?limit=100&offset=0"
      #
      # @example Array parameters (repeated keys)
      #   build_endpoint('/applications/', solution: 'sol_123', fields: ['id', 'name'])
      #   #=> "/applications/?solution=sol_123&fields=id&fields=name"
      #
      # @example URL encoding
      #   build_endpoint('/comments/', record: 'rec_abc%123')
      #   #=> "/comments/?record=rec_abc%25123"
      #
      # @example Empty parameters filtered out
      #   build_endpoint('/applications/', solution: nil, fields: [])
      #   #=> "/applications/"
      def build_endpoint(path, **params)
        # Filter out nil and empty values
        filtered_params = params.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }

        return path if filtered_params.empty?

        query_parts = filtered_params.flat_map do |key, value|
          if value.is_a?(Array)
            # Repeat key for each array element (e.g., fields=id&fields=name)
            value.map { |val| "#{key}=#{URI.encode_www_form_component(val.to_s)}" }
          else
            ["#{key}=#{URI.encode_www_form_component(value.to_s)}"]
          end
        end

        "#{path}?#{query_parts.join('&')}"
      end

      # Check if cache should be used for this request.
      #
      # Centralizes the cache decision logic used across all modules.
      #
      # @param bypass [Boolean] Whether to bypass cache (default: false)
      # @return [Boolean] true if cache should be used
      # @example
      #   return fetch_from_api if should_bypass_cache?(bypass: bypass_cache)
      def should_bypass_cache?(bypass: false)
        !cache_enabled? || bypass
      end

      # Track and log response size with token estimation.
      #
      # Calculates token usage, logs success message with count, and logs token metrics.
      # Returns the result unchanged for method chaining.
      #
      # @param result [Hash, Array] Response data to track
      # @param message [String] Success message to log (auto-prefixed with ✓)
      # @return [Hash, Array] The unchanged result for method chaining
      # @example
      #   result = { 'solutions' => solutions, 'count' => solutions.size }
      #   track_response_size(result, "Found #{solutions.size} solutions")
      def track_response_size(result, message)
        tokens = estimate_tokens(JSON.generate(result))
        total_tokens = update_token_usage(tokens)
        log_metric("✓ #{message} | +#{tokens} tokens (Total: #{total_tokens})")
        result
      end

      # Build standard collection response structure.
      #
      # Creates consistent response format with collection name, items, count, and metadata.
      # Standardizes the pattern used across all list operations.
      #
      # @param items [Array] Collection items
      # @param collection_name [String, Symbol] Key name for the collection in response
      # @param metadata [Hash] Additional metadata fields (e.g., total_count, filtered_by)
      # @return [Hash] Formatted response with collection, count, and metadata
      # @example Basic usage
      #   build_collection_response(solutions, :solutions)
      #   #=> {"solutions" => [...], "count" => 10}
      #
      # @example With metadata
      #   build_collection_response(members, :members, total_count: 150, filtered: true)
      #   #=> {"members" => [...], "count" => 25, "total_count" => 150, "filtered" => true}
      def build_collection_response(items, collection_name, **metadata)
        result = {
          collection_name.to_s => items,
          'count' => items.size
        }

        # Merge metadata with string keys
        metadata.each do |key, value|
          result[key.to_s] = value
        end

        result
      end

      # Handle SmartSuite API response format.
      #
      # Validates response structure and extracts items array if present.
      # Returns empty array if response is nil, malformed, or empty.
      #
      # @param response [Hash, nil] API response
      # @param items_key [String] Key for items array (default: 'items')
      # @return [Array] Items array from response or empty array
      # @example
      #   response = api_request(:get, '/solutions/')
      #   items = extract_items_from_response(response)
      def extract_items_from_response(response, items_key = 'items')
        return [] unless response.is_a?(Hash)
        return [] unless response[items_key].is_a?(Array)

        response[items_key]
      end

      # Format timestamp for logging with millisecond precision.
      #
      # @param time [Time] Time object to format
      # @return [String] Formatted timestamp
      # @example
      #   format_timestamp(Time.now) #=> "2025-01-16 10:30:45.123"
      def format_timestamp(time = Time.now)
        time.strftime('%Y-%m-%d %H:%M:%S.%L')
      end

      # Log cache hit with standardized format.
      #
      # @param resource_type [String] Type of resource (e.g., 'solutions', 'tables')
      # @param count [Integer] Number of items in cache
      # @param cache_key [String, nil] Optional cache key identifier
      # @return [void]
      # @example
      #   log_cache_hit('solutions', 110)
      #   log_cache_hit('tables', 25, 'sol_abc123')
      def log_cache_hit(resource_type, count, cache_key = nil)
        details = { count: count }
        details[:key] = cache_key if cache_key
        SmartSuite::Logger.cache('hit', resource_type, details)
      end

      # Log cache miss with standardized format.
      #
      # @param resource_type [String] Type of resource (e.g., 'solutions', 'tables')
      # @param cache_key [String, nil] Optional cache key identifier
      # @return [void]
      # @example
      #   log_cache_miss('solutions')
      #   log_cache_miss('tables', 'sol_abc123')
      def log_cache_miss(resource_type, cache_key = nil)
        details = { status: 'fetching from API' }
        details[:key] = cache_key if cache_key
        SmartSuite::Logger.cache('miss', resource_type, details)
      end

      # Check cache and return cached data if available.
      #
      # This helper centralizes the cache-first pattern used across all API modules.
      # It handles the cache check, logging, and returns cached data or nil.
      #
      # @param resource_type [String] Type of resource for logging (e.g., 'solutions', 'tables')
      # @param cache_key [String, nil] Optional cache key for logging (e.g., 'sol_123')
      # @param bypass [Boolean] Whether to bypass cache entirely (default: false)
      # @yield Block that calls the cache getter method and returns cached data or nil
      # @return [Object, nil] Cached data if hit, nil if miss or bypassed
      # @example Basic usage
      #   cached = with_cache_check('solutions') { @cache.get_cached_solutions }
      #   return format_response(cached) if cached
      #
      # @example With cache key for logging
      #   cached = with_cache_check('tables', solution_id) { @cache.get_cached_table_list(solution_id) }
      #
      # @example With bypass condition
      #   cached = with_cache_check('tables', nil, bypass: fields&.any?) do
      #     @cache.get_cached_table_list(solution_id)
      #   end
      def with_cache_check(_resource_type, _cache_key = nil, bypass: false)
        return nil if should_bypass_cache? || bypass

        # Cache layer logs hits/misses, so we just return the data
        yield
      end

      # Extract items from response, handling both Array and Hash formats.
      #
      # SmartSuite API responses can be either:
      # - Direct Array (e.g., /applications/ endpoint)
      # - Hash with 'items' key (e.g., /solutions/ endpoint)
      #
      # This helper normalizes both formats to an Array.
      #
      # @param response [Array, Hash] API response
      # @param items_key [String] Key for items in Hash response (default: 'items')
      # @return [Array] Items array
      # @example
      #   items = extract_items_safely(response)
      def extract_items_safely(response, items_key = 'items')
        response.is_a?(Array) ? response : extract_items_from_response(response, items_key)
      end

      # Ensure records are cached for a table, populating cache if needed.
      #
      # This helper centralizes the cache-first aggressive fetch strategy.
      # When cache is invalid/expired, fetches ALL records and caches them.
      # This enables efficient local querying and reduces subsequent API calls.
      #
      # @param table_id [String] Table identifier
      # @return [void]
      # @example
      #   ensure_records_cached('tbl_123')
      #   # Cache is now populated, subsequent queries are local
      def ensure_records_cached(table_id)
        return unless cache_enabled?

        # Check if cache is valid
        if @cache.cache_valid?(table_id)
          # Track cache hit
          @cache.track_cache_hit(table_id)
          return
        end

        # Track cache miss
        @cache.track_cache_miss(table_id)
        SmartSuite::Logger.cache('miss', table_id, action: 'fetching all records')

        # Fetch table structure (use JSON format for internal processing)
        structure = get_table(table_id, format: :json)

        # Fetch ALL records (aggressive strategy)
        all_records = fetch_all_records(table_id)

        # Cache records
        @cache.cache_table_records(table_id, structure, all_records)

        SmartSuite::Logger.cache('cached', table_id, records: all_records.size)
      end

      # Format a single object response based on format parameter.
      #
      # This helper provides consistent formatting across all single-object
      # operations (get_record, create_record, get_team, etc.).
      #
      # @param data [Hash] Data to format
      # @param format [Symbol] Output format: :toon (default) or :json
      # @param message [String] Log message for metrics
      # @return [String, Hash] TOON string or JSON hash depending on format
      # @example
      #   format_single_response(record, :toon)
      #   format_single_response(team, :json)
      def format_single_response(data, format)
        case format
        when :toon
          require_relative '../formatters/toon_formatter'
          SmartSuite::Formatters::ToonFormatter.format(data)
        else # :json
          data
        end
      end

      # Format an array response based on format parameter.
      #
      # This helper provides consistent formatting across all array-returning
      # operations (bulk_add_records, bulk_update_records, etc.).
      #
      # @param data [Array] Array data to format
      # @param format [Symbol] Output format: :toon (default) or :json
      # @param collection_name [Symbol] Name for the collection wrapper
      # @param message [String] Log message for metrics
      # @return [String, Hash] TOON string or JSON hash depending on format
      # @example
      #   format_array_response(records, :toon, :records)
      def format_array_response(data, format, collection_name)
        case format
        when :toon
          require_relative '../formatters/toon_formatter'
          wrapped = { collection_name.to_s => data }
          SmartSuite::Formatters::ToonFormatter.format(wrapped)
        else # :json - return raw array for backward compatibility
          data
        end
      end

      # Fetch all records from a table using paginated API calls.
      #
      # Uses list endpoint with hydrated=true to get complete data including
      # linked records, users, and other reference fields. This eliminates the
      # need for separate get_record calls.
      #
      # @param table_id [String] Table identifier
      # @return [Array<Hash>] Array of complete record hashes
      # @example
      #   records = fetch_all_records('tbl_123')
      def fetch_all_records(table_id)
        all_records = []
        offset = 0
        limit = Pagination::FETCH_ALL_LIMIT

        loop do
          # Build endpoint with query parameters
          base_path = "/applications/#{table_id}/records/list/"
          endpoint = build_endpoint(base_path, limit: limit, offset: offset, hydrated: true)
          response = api_request(:post, endpoint, nil)

          records = response['items'] || []
          break if records.empty?

          all_records.concat(records)
          offset += limit

          # Break if we got fewer records than requested (last page)
          break if records.size < limit
        end

        all_records
      end
    end
  end
end
