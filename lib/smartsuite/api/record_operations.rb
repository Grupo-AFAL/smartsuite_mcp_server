# frozen_string_literal: true

require_relative '../filter_builder'
require_relative 'base'

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
    # Uses Base module for common API patterns (validation, endpoint building, cache coordination).
    module RecordOperations
      include Base

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
      # @return [String] Plain text formatted records with total/filtered counts
      # @raise [ArgumentError] If table_id is missing
      # @example
      #   list_records('tbl_123', 10, 0, fields: ['status', 'priority'])
      def list_records(table_id, limit = nil, offset = 0, filter: nil, sort: nil, fields: nil, hydrated: true)
        validate_required_parameter!('table_id', table_id)

        # Handle nil values (when called via MCP with missing parameters)
        limit = 10 if limit.nil?
        offset ||= 0

        # VALIDATION: Require fields parameter to prevent excessive context usage
        if !fields || fields.empty?
          error_msg = "ERROR: You must specify 'fields' parameter to control token usage.\n\n" \
                      "Example:\n  " \
                      "list_records(table_id, limit, offset, fields: ['status', 'priority'])\n\n" \
                      'This ensures you only fetch the data you need.'
          return error_msg
        end

        # Try cache-first strategy if enabled
        unless should_bypass_cache?
          return list_records_from_cache(table_id, limit, offset, filter, sort, fields,
                                         hydrated)
        end

        # Fallback to direct API call (cache disabled)
        list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated)
      end

      private

      # List records using cache (aggressive fetch strategy)
      def list_records_from_cache(table_id, limit, offset, filter, sort, fields, hydrated)
        # Ensure cache is populated
        ensure_records_cached(table_id)

        # Build query with filters
        query = @cache.query(table_id)

        # Apply filters if provided
        query = apply_filters_to_query(query, filter) if filter && filter['fields']&.any?

        # Apply sorting if provided
        query = apply_sorting_to_query(query, sort) if sort.is_a?(Array) && sort.any?

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
      #
      # Delegates to FilterBuilder for conversion from SmartSuite filter format
      # to cache query conditions.
      #
      # @param query [SmartSuite::Cache::Query] Cache query builder instance
      # @param filter [Hash] SmartSuite filter hash
      # @return [SmartSuite::Cache::Query] Query with filters applied
      def apply_filters_to_query(query, filter)
        SmartSuite::FilterBuilder.apply_to_query(query, filter)
      end

      # Apply SmartSuite sort criteria to cache query
      #
      # SmartSuite sort format: [{field: 'field_slug', direction: 'asc|desc'}, ...]
      # Applies all sort criteria in order.
      #
      # @param query [SmartSuite::Cache::Query] Cache query builder instance
      # @param sort [Array<Hash>] SmartSuite sort array
      # @return [SmartSuite::Cache::Query] Query with sorting applied
      def apply_sorting_to_query(query, sort)
        return query unless sort.is_a?(Array) && sort.any?

        # Apply all sort criteria in order
        sort.each do |sort_criterion|
          field_slug = sort_criterion['field'] || sort_criterion[:field]
          direction = sort_criterion['direction'] || sort_criterion[:direction] || 'ASC'
          query.order(field_slug, direction.upcase)
        end

        query
      end

      # Direct API call (original behavior, used when cache disabled/bypassed)
      def list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated)
        # Build endpoint with query parameters using Base helper
        base_path = "/applications/#{table_id}/records/list/"
        endpoint = build_endpoint(base_path, limit: limit, offset: offset, hydrated: hydrated || nil)

        # Build body with filter and sort (if provided)
        body = {}
        body[:filter] = sanitize_filter_for_api(filter) if filter
        body[:sort] = sort if sort

        # Make request with endpoint and body
        response = api_request(:post, endpoint, body.empty? ? nil : body)

        # Apply aggressive filtering to reduce response size
        # Returns plain text format to save ~40% tokens vs JSON
        filter_records_response(response, fields, plain_text: true, hydrated: hydrated)
      end

      # Sanitize filter before sending to SmartSuite API.
      #
      # The SmartSuite API has specific requirements for certain comparison operators:
      # - is_empty and is_not_empty must have null value (not empty string)
      #
      # @param filter [Hash] Filter criteria
      # @return [Hash] Sanitized filter
      def sanitize_filter_for_api(filter)
        return filter unless filter.is_a?(Hash) && filter['fields']

        sanitized_filter = filter.dup
        sanitized_filter['fields'] = filter['fields'].map do |field_filter|
          sanitized_field = field_filter.dup
          comparison = sanitized_field['comparison']

          # For empty check operators, ensure value is null
          sanitized_field['value'] = nil if %w[is_empty is_not_empty].include?(comparison)

          sanitized_field
        end

        sanitized_filter
      end

      # Ensure records are cached for a table
      def ensure_records_cached(table_id)
        # Check if cache is valid
        if @cache.cache_valid?(table_id)
          # Track cache hit
          @cache.track_cache_hit(table_id)
          return
        end

        # Track cache miss
        @cache.track_cache_miss(table_id)
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
      #
      # Uses list endpoint with hydrated=true to get complete data including
      # linked records, users, and other reference fields. This eliminates the
      # need for separate get_record calls.
      #
      # @param table_id [String] Table identifier
      # @return [Array<Hash>] Array of complete record hashes
      def fetch_all_records(table_id)
        all_records = []
        offset = 0
        limit = Base::Pagination::FETCH_ALL_LIMIT # Use constant from Base

        loop do
          # Build endpoint with query parameters using Base helper
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

      public

      # Retrieves a single record by ID.
      #
      # Returns complete record with all fields.
      # Uses cache-first strategy - only makes API call if record not cached.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @return [Hash] Complete record data
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   get_record('tbl_123', 'rec_abc')
      def get_record(table_id, record_id)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        # Try to get from cache first
        if @cache
          cached_record = @cache.get_cached_record(table_id, record_id)
          if cached_record
            log_metric("✓ Retrieved record from cache: #{record_id}")
            # Process SmartDoc fields to extract only HTML
            return process_smartdoc_fields(cached_record)
          end
        end

        # Cache miss or disabled - fetch from API
        log_metric("→ Getting record from API: #{record_id}")
        record = api_request(:get, "/applications/#{table_id}/records/#{record_id}/")
        # Process SmartDoc fields in API response too
        process_smartdoc_fields(record)
      end

      # Process SmartDoc fields in a record to extract only HTML content.
      #
      # SmartDoc fields contain {data, html, preview, yjsData} but AI only needs HTML.
      # This reduces token usage by ~60-70% for rich text fields.
      #
      # Cache stores these as JSON strings, so we parse them first before checking.
      #
      # @param record [Hash] Record with potential SmartDoc fields
      # @return [Hash] Record with SmartDoc fields replaced by HTML strings
      def process_smartdoc_fields(record)
        return record unless record.is_a?(Hash)

        record.transform_values do |value|
          # Try to parse JSON strings
          parsed_value = value.is_a?(String) ? parse_json_safe(value) : value

          # Check if parsed value is a SmartDoc structure
          if smartdoc_value?(parsed_value)
            # Extract only HTML content
            parsed_value['html'] || parsed_value[:html] || ''
          else
            value # Return original value if not SmartDoc
          end
        end
      end

      # Safely parse JSON string, returning nil if parsing fails.
      #
      # @param str [String] JSON string to parse
      # @return [Object, nil] Parsed JSON or nil if invalid
      def parse_json_safe(str)
        JSON.parse(str)
      rescue JSON::ParserError, TypeError
        nil
      end

      # Determines if a value is a SmartDoc field.
      #
      # @param value [Object] Value to check
      # @return [Boolean] True if value is a SmartDoc structure
      def smartdoc_value?(value)
        return false unless value.is_a?(Hash)

        # SmartDoc has both 'data' and 'html' keys
        has_data = value.key?('data') || value.key?(:data)
        has_html = value.key?('html') || value.key?(:html)

        has_data && has_html
      end

      # Creates a new record in a table.
      #
      # @param table_id [String] Table identifier
      # @param data [Hash] Record data as field_slug => value pairs
      # @return [Hash] Created record with ID
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   create_record('tbl_123', {'title' => 'New Task', 'status' => 'Active'})
      def create_record(table_id, data)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('data', data, Hash)

        api_request(:post, "/applications/#{table_id}/records/", data)
      end

      # Updates an existing record.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @param data [Hash] Record data to update as field_slug => value pairs
      # @return [Hash] Updated record data
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   update_record('tbl_123', 'rec_abc', {'status' => 'Completed'})
      def update_record(table_id, record_id, data)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)
        validate_required_parameter!('data', data, Hash)

        api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)
      end

      # Deletes a record from a table.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to delete
      # @return [Hash] Deletion confirmation
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   delete_record('tbl_123', 'rec_abc')
      def delete_record(table_id, record_id)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        api_request(:delete, "/applications/#{table_id}/records/#{record_id}/")
      end

      # Creates multiple records in a single request (bulk operation).
      #
      # More efficient than multiple create_record calls when adding many records.
      # Accepts an array of record data hashes.
      #
      # @param table_id [String] Table identifier
      # @param records [Array<Hash>] Array of record data hashes (field_slug => value)
      # @return [Array<Hash>] Array of created records with IDs
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   bulk_add_records('tbl_123', [
      #     {'title' => 'Task 1', 'status' => 'Active'},
      #     {'title' => 'Task 2', 'status' => 'Pending'}
      #   ])
      def bulk_add_records(table_id, records)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('records', records, Array)

        api_request(:post, "/applications/#{table_id}/records/bulk/", { 'items' => records })
      end

      # Updates multiple records in a single request (bulk operation).
      #
      # More efficient than multiple update_record calls when updating many records.
      # Each record hash must include 'id' field along with fields to update.
      #
      # @param table_id [String] Table identifier
      # @param records [Array<Hash>] Array of record hashes with 'id' and fields to update
      # @return [Array<Hash>] Array of updated records
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   bulk_update_records('tbl_123', [
      #     {'id' => 'rec_abc', 'status' => 'Completed'},
      #     {'id' => 'rec_def', 'status' => 'In Progress'}
      #   ])
      def bulk_update_records(table_id, records)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('records', records, Array)

        api_request(:patch, "/applications/#{table_id}/records/bulk/", { 'items' => records })
      end

      # Deletes multiple records in a single request (bulk operation).
      #
      # More efficient than multiple delete_record calls when deleting many records.
      # This performs a soft delete - records can be restored using restore_deleted_record.
      #
      # @param table_id [String] Table identifier
      # @param record_ids [Array<String>] Array of record IDs to delete
      # @return [Hash] Deletion confirmation
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example
      #   bulk_delete_records('tbl_123', ['rec_abc', 'rec_def', 'rec_ghi'])
      def bulk_delete_records(table_id, record_ids)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_ids', record_ids, Array)

        api_request(:patch, "/applications/#{table_id}/records/bulk_delete/", { 'items' => record_ids })
      end

      # Gets a public URL for a file attached to a record.
      #
      # The file handle can be found in file/image field values.
      # Returns a public URL with a 20-year lifetime.
      #
      # @param file_handle [String] File handle from a file/image field
      # @return [Hash] Hash containing 'url' key with the public file URL
      # @raise [ArgumentError] If file_handle is missing
      # @example
      #   get_file_url('handle_xyz')
      #   # => {"url" => "https://..."}
      def get_file_url(file_handle)
        validate_required_parameter!('file_handle', file_handle)

        api_request(:get, "/shared-files/#{file_handle}/url/")
      end

      # Lists deleted records from a solution.
      #
      # Returns records that have been soft-deleted and can be restored.
      # The preview parameter limits which fields are returned.
      #
      # @param solution_id [String] Solution identifier
      # @param preview [Boolean] If true, returns limited fields (default: true)
      # @return [Array<Hash>] Array of deleted records with deletion metadata
      # @raise [ArgumentError] If solution_id is missing
      # @example
      #   list_deleted_records('sol_123', preview: true)
      def list_deleted_records(solution_id, preview: true)
        validate_required_parameter!('solution_id', solution_id)

        # Build endpoint with query parameter
        endpoint = build_endpoint('/deleted-records/', preview: preview)

        # Body contains solution_id
        body = { solution_id: solution_id }

        api_request(:post, endpoint, body)
      end

      # Restores a deleted record.
      #
      # Restores a soft-deleted record back to the table.
      # The restored record will have "(Restored)" appended to its title.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to restore
      # @return [Hash] Restored record data
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   restore_deleted_record('tbl_123', 'rec_abc')
      def restore_deleted_record(table_id, record_id)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        api_request(:post, "/applications/#{table_id}/records/#{record_id}/restore/", {})
      end

      # Attach a file to a record by URL
      #
      # @param table_id [String] the ID of the table containing the record
      # @param record_id [String] the ID of the record to attach the file to
      # @param file_field_slug [String] the slug of the file/image field
      # @param file_urls [Array<String>] array of URLs to files to attach
      #   SmartSuite will download the files from these URLs and attach them to the record
      # @return [Hash] the updated record object
      # @raise [ArgumentError] if table_id, record_id, file_field_slug, or file_urls is missing
      # @raise [RuntimeError] if the API request fails
      #
      # @example Attach a single file
      #   attach_file('tbl_123', 'rec_456', 'attachments', ['https://example.com/file.pdf'])
      #
      # @example Attach multiple files
      #   attach_file('tbl_123', 'rec_456', 'images', [
      #     'https://example.com/image1.jpg',
      #     'https://example.com/image2.jpg'
      #   ])
      #
      # @note This operation uses the update_record endpoint (PATCH) but is specifically
      #   designed for attaching files by URL. SmartSuite downloads the files from the
      #   provided URLs and attaches them to the specified field.
      # @note The file URLs must be publicly accessible for SmartSuite to download them.
      def attach_file(table_id, record_id, file_field_slug, file_urls)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)
        validate_required_parameter!('file_field_slug', file_field_slug)
        validate_required_parameter!('file_urls', file_urls, Array)

        body = {
          'id' => record_id,
          file_field_slug => file_urls
        }

        api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", body)
      end
    end
  end
end
