module SmartSuite
  module API
    # RecordOperations handles CRUD operations on table records.
    #
    # This module provides methods for:
    # - Listing records with filtering, sorting, and pagination
    # - Getting individual records
    # - Creating, updating, and deleting records
    #
    # Implements caching for efficient queries and aggressive validation to minimize token usage.
    module RecordOperations
      # Lists records from a table with filtering, sorting, and field selection.
      #
      # When cache is enabled:
      # - Checks cache validity
      # - If invalid/expired, fetches ALL records and caches them
      # - Queries cache for results
      #
      # When cache is disabled:
      # - Falls back to direct API calls with pagination
      #
      # IMPORTANT: Requires either `fields` parameter or `summary_only: true` to
      # prevent excessive context usage.
      #
      # Returns plain text format by default (saves ~40% tokens vs JSON).
      #
      # @param table_id [String] Table identifier
      # @param limit [Integer] Maximum records to return (default: 5, or nil to use default)
      # @param offset [Integer] Number of records to skip for pagination (default: 0)
      # @param filter [Hash, nil] Filter criteria following SmartSuite filter syntax
      # @param sort [Array<Hash>, nil] Sort criteria (field + direction)
      # @param fields [Array<String>, nil] Field slugs to include in response
      # @param summary_only [Boolean] Return statistics instead of records (default: false)
      # @param full_content [Boolean] Return full field values without truncation (default: false)
      # @param bypass_cache [Boolean] Force API call even if cache enabled (default: false)
      # @return [String, Hash] Plain text formatted records or summary hash
      def list_records(table_id, limit = nil, offset = 0, filter: nil, sort: nil, fields: nil, summary_only: false, full_content: false, bypass_cache: false)
        # Handle nil values (when called via MCP with missing parameters)
        # If limit is nil (not specified), use default of 5
        limit = 5 if limit.nil?
        offset ||= 0

        # VALIDATION: Require fields or summary_only to prevent excessive context usage
        if !summary_only && (!fields || fields.empty?)
          error_msg = "ERROR: You must specify 'fields' or use 'summary_only: true'\n\n" +
                      "Correct examples:\n" +
                      "  list_records(table_id, fields: ['status', 'priority'])\n" +
                      "  list_records(table_id, summary_only: true)\n\n" +
                      "This prevents excessive context consumption."
          return {'error' => error_msg}
        end

        # Try cache-first strategy if enabled
        if cache_enabled? && !bypass_cache
          return list_records_from_cache(table_id, limit, offset, fields, summary_only, full_content)
        end

        # Fallback to direct API call (cache disabled or bypassed)
        list_records_direct_api(table_id, limit, offset, filter, sort, fields, summary_only, full_content)
      end

      private

      # List records using cache (aggressive fetch strategy)
      def list_records_from_cache(table_id, limit, offset, fields, summary_only, full_content)
        # Ensure cache is populated
        ensure_records_cached(table_id)

        # Query cache
        query = @cache.query(table_id)

        # Apply limit and offset
        query = query.limit(limit) if limit
        query = query.offset(offset) if offset

        # Execute query
        results = query.execute

        # Format results similar to API response
        response = {
          'items' => results,
          'total_count' => @cache.query(table_id).count
        }

        # If summary_only, return statistics
        if summary_only
          return generate_summary(response)
        end

        # Apply filtering and formatting
        filter_records_response(response, fields, plain_text: true, full_content: full_content)
      end

      # Direct API call (original behavior, used when cache disabled/bypassed)
      def list_records_direct_api(table_id, limit, offset, filter, sort, fields, summary_only, full_content)
        # Build query params for limit and offset
        query_params = "?limit=#{limit}&offset=#{offset}"

        # Build body with filter and sort (if provided)
        body = {}
        body[:filter] = filter if filter
        body[:sort] = sort if sort

        # Make request with query params and body
        response = api_request(:post, "/applications/#{table_id}/records/list/#{query_params}", body.empty? ? nil : body)

        # If summary_only, return just statistics
        if summary_only
          return generate_summary(response)
        end

        # Apply aggressive filtering to reduce response size
        # Returns plain text format to save ~40% tokens vs JSON
        filter_records_response(response, fields, plain_text: true, full_content: full_content)
      end

      # Ensure records are cached for a table
      def ensure_records_cached(table_id)
        # Check if cache is valid
        return if @cache.cache_valid?(table_id)

        log_metric("→ Cache miss for #{table_id}, fetching all records...")

        # Fetch table structure
        structure = get_table(table_id)

        # Fetch ALL records (aggressive strategy)
        all_records = fetch_all_records(table_id)

        # Cache records
        @cache.cache_table_records(table_id, structure, all_records)

        log_metric("✓ Cached #{all_records.size} records for #{table_id}")
      end

      # Fetch all records from a table (paginated API calls)
      def fetch_all_records(table_id)
        all_records = []
        offset = 0
        limit = 100  # Batch size

        loop do
          query_params = "?limit=#{limit}&offset=#{offset}"
          response = api_request(:post, "/applications/#{table_id}/records/list/#{query_params}", nil)

          records = response['items'] || []
          break if records.empty?

          all_records.concat(records)
          offset += limit

          # Break if we got fewer records than requested (last page)
          break if records.size < limit
        end

        all_records
      end

      public

      # Retrieves a single record by ID.
      #
      # Returns complete record with all fields.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @return [Hash] Complete record data
      def get_record(table_id, record_id)
        api_request(:get, "/applications/#{table_id}/records/#{record_id}/")
      end

      # Creates a new record in a table.
      #
      # Invalidates cache for this table after creation.
      #
      # @param table_id [String] Table identifier
      # @param data [Hash] Record data as field_slug => value pairs
      # @return [Hash] Created record with ID
      def create_record(table_id, data)
        result = api_request(:post, "/applications/#{table_id}/records/", data)

        # Invalidate cache (new record added)
        if cache_enabled?
          @cache.invalidate_table_cache(table_id)
          log_metric("→ Cache invalidated for #{table_id} (record created)")
        end

        result
      end

      # Updates an existing record.
      #
      # Invalidates cache for this table after update.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @param data [Hash] Record data to update as field_slug => value pairs
      # @return [Hash] Updated record data
      def update_record(table_id, record_id, data)
        result = api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)

        # Invalidate cache (record modified)
        if cache_enabled?
          @cache.invalidate_table_cache(table_id)
          log_metric("→ Cache invalidated for #{table_id} (record updated)")
        end

        result
      end

      # Deletes a record from a table.
      #
      # Invalidates cache for this table after deletion.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to delete
      # @return [Hash] Deletion confirmation
      def delete_record(table_id, record_id)
        result = api_request(:delete, "/applications/#{table_id}/records/#{record_id}/")

        # Invalidate cache (record deleted)
        if cache_enabled?
          @cache.invalidate_table_cache(table_id)
          log_metric("→ Cache invalidated for #{table_id} (record deleted)")
        end

        result
      end
    end
  end
end
