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
      # TIP: Specify `fields` parameter to minimize token usage by only returning needed fields.
      #
      # Returns plain text format by default (saves ~40% tokens vs JSON).
      # Always includes total_records and filtered_records counts to help AI make informed decisions.
      #
      # @param table_id [String] Table identifier
      # @param limit [Integer] Maximum records to return (default: 10)
      # @param offset [Integer] Number of records to skip for pagination (default: 0)
      # @param filter [Hash, nil] Filter criteria following SmartSuite filter syntax
      # @param sort [Array<Hash>, nil] Sort criteria (field + direction)
      # @param fields [Array<String>, nil] Field slugs to include in response (recommended for token efficiency)
      # @param hydrated [Boolean] Fetch human-readable values for linked records, users, etc. (default: true)
      # @param bypass_cache [Boolean] Force API call even if cache enabled (default: false)
      # @return [String] Plain text formatted records with total/filtered counts
      def list_records(table_id, limit = nil, offset = 0, filter: nil, sort: nil, fields: nil, hydrated: true, bypass_cache: false)
        # Handle nil values (when called via MCP with missing parameters)
        limit = 10 if limit.nil?
        offset ||= 0

        # VALIDATION: Require fields parameter to prevent excessive context usage
        if !fields || fields.empty?
          error_msg = "ERROR: You must specify 'fields' parameter to control token usage.\n\n" +
                      "Example:\n" +
                      "  list_records(table_id, limit, offset, fields: ['status', 'priority'])\n\n" +
                      "This ensures you only fetch the data you need."
          return error_msg
        end

        # Try cache-first strategy if enabled
        if cache_enabled? && !bypass_cache
          return list_records_from_cache(table_id, limit, offset, filter, fields, hydrated)
        end

        # Fallback to direct API call (cache disabled or bypassed)
        list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated)
      end

      private

      # List records using cache (aggressive fetch strategy)
      def list_records_from_cache(table_id, limit, offset, filter, fields, hydrated)
        # Ensure cache is populated
        ensure_records_cached(table_id)

        # Build query with filters
        query = @cache.query(table_id)

        # Apply filters if provided
        if filter && filter['fields'] && filter['fields'].any?
          query = apply_filters_to_query(query, filter)
        end

        # Get total record count (before limit/offset)
        total_count = query.count

        # Apply limit and offset
        query = query.limit(limit) if limit
        query = query.offset(offset) if offset
        results = query.execute

        # Get grand total (all records in table, unfiltered)
        grand_total = @cache.query(table_id).count

        # Format results similar to API response
        response = {
          'items' => results,
          'total_count' => grand_total,
          'filtered_count' => total_count
        }

        # Apply filtering and formatting with counts
        filter_records_response(response, fields, plain_text: true, hydrated: hydrated)
      end

      # Apply SmartSuite filter criteria to cache query
      def apply_filters_to_query(query, filter)
        return query unless filter && filter['fields']

        filter['fields'].each do |field_filter|
          field_slug = field_filter['field']
          comparison = field_filter['comparison']
          value = field_filter['value']

          # Convert SmartSuite comparison operators to cache query format
          condition = case comparison
          when 'is', 'is_equal_to'
            value
          when 'is_not', 'is_not_equal_to'
            { ne: value }
          when 'is_greater_than'
            { gt: value }
          when 'is_less_than'
            { lt: value }
          when 'is_equal_or_greater_than'
            { gte: value }
          when 'is_equal_or_less_than'
            { lte: value }
          when 'contains'
            { contains: value }
          when 'not_contains', 'does_not_contain'
            { not_contains: value }
          when 'is_empty'
            nil
          when 'is_not_empty'
            { not_null: true }
          when 'has_any_of'
            { has_any_of: value }
          when 'has_all_of'
            { has_all_of: value }
          when 'is_exactly'
            { is_exactly: value }
          when 'has_none_of'
            { has_none_of: value }
          when 'is_before'
            { lt: value }
          when 'is_after'
            { gt: value }
          when 'is_on_or_before'
            { lte: value }
          when 'is_on_or_after'
            { gte: value }
          else
            value  # Default to equality
          end

          # Apply filter to query
          query = query.where(field_slug.to_sym => condition)
        end

        query
      end

      # Direct API call (original behavior, used when cache disabled/bypassed)
      def list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated)
        # Build query params for limit, offset, and hydrated
        query_params = "?limit=#{limit}&offset=#{offset}"
        query_params += "&hydrated=#{hydrated}" if hydrated

        # Build body with filter and sort (if provided)
        body = {}
        body[:filter] = filter if filter
        body[:sort] = sort if sort

        # Make request with query params and body
        response = api_request(:post, "/applications/#{table_id}/records/list/#{query_params}", body.empty? ? nil : body)

        # Apply aggressive filtering to reduce response size
        # Returns plain text format to save ~40% tokens vs JSON
        filter_records_response(response, fields, plain_text: true, hydrated: hydrated)
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
        limit = 1000  # Batch size (use 1000 to minimize API calls)

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
      # @param table_id [String] Table identifier
      # @param data [Hash] Record data as field_slug => value pairs
      # @return [Hash] Created record with ID
      def create_record(table_id, data)
        api_request(:post, "/applications/#{table_id}/records/", data)
      end

      # Updates an existing record.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @param data [Hash] Record data to update as field_slug => value pairs
      # @return [Hash] Updated record data
      def update_record(table_id, record_id, data)
        api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)
      end

      # Deletes a record from a table.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to delete
      # @return [Hash] Deletion confirmation
      def delete_record(table_id, record_id)
        api_request(:delete, "/applications/#{table_id}/records/#{record_id}/")
      end
    end
  end
end
