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
      # Returns TOON format by default (~50-60% token savings vs JSON).
      # Always includes total_records and filtered_records counts to help AI make informed decisions.
      #
      # @param table_id [String] Table identifier
      # @param limit [Integer] Maximum records to return (default: 10)
      # @param offset [Integer] Number of records to skip for pagination (default: 0)
      # @param filter [Hash, nil] Filter criteria following SmartSuite filter syntax
      # @param sort [Array<Hash>, nil] Sort criteria (field + direction)
      # @param fields [Array<String>, nil] Field slugs to include in response (recommended for token efficiency)
      # @param hydrated [Boolean] Fetch human-readable values for linked records, users, etc. (default: true)
      # @param format [Symbol] Output format: :toon (default, ~50-60% token savings) or :json
      # @return [String] Formatted records with total/filtered counts
      # @raise [ArgumentError] If table_id is missing
      # @example
      #   list_records('tbl_123', 10, 0, fields: ['status', 'priority'])
      #   list_records('tbl_123', 10, 0, fields: ['status'], format: :json)
      def list_records(table_id, limit = nil, offset = 0, filter: nil, sort: nil, fields: nil, hydrated: true,
                       format: :toon)
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
                                         hydrated, format)
        end

        # Fallback to direct API call (cache disabled)
        list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated, format)
      end

      private

      # List records using cache (aggressive fetch strategy)
      def list_records_from_cache(table_id, limit, offset, filter, sort, fields, hydrated, format)
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
        format_options = format_to_options(format)
        filter_records_response(response, fields, **format_options, hydrated: hydrated)
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
      def list_records_direct_api(table_id, limit, offset, filter, sort, fields, hydrated, format)
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
        format_options = format_to_options(format)
        filter_records_response(response, fields, **format_options, hydrated: hydrated)
      end

      # Converts format symbol to filter_records_response options.
      #
      # @param format [Symbol] Output format (:toon or :json)
      # @return [Hash] Options hash for filter_records_response
      def format_to_options(format)
        case format
        when :json
          {}
        else # :toon (default)
          { toon: true }
        end
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

      # NOTE: ensure_records_cached and fetch_all_records are now in Base module
      # for sharing across all API modules (WorkspaceOperations, RecordOperations, etc.)

      public

      # Retrieves a single record by ID.
      #
      # Returns complete record with all fields.
      # Uses cache-first strategy - only makes API call if record not cached.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Record data in requested format
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   get_record('tbl_123', 'rec_abc')
      #   get_record('tbl_123', 'rec_abc', format: :json)
      def get_record(table_id, record_id, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        record = nil

        # Try to get from cache first
        if @cache
          cached_record = @cache.get_cached_record(table_id, record_id)
          if cached_record
            log_metric("✓ Retrieved record from cache: #{record_id}")
            # Process SmartDoc fields to extract only HTML
            record = process_smartdoc_fields(cached_record)
          end
        end

        unless record
          # Cache miss or disabled - fetch from API
          log_metric("→ Getting record from API: #{record_id}")
          record = api_request(:get, "/applications/#{table_id}/records/#{record_id}/")
          # Process SmartDoc fields in API response too
          record = process_smartdoc_fields(record)
        end

        format_single_response(record, format)
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
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~95% token reduction) and updates cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Hash, String] Created record with ID (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example Minimal response (default, 95% token savings)
      #   create_record('tbl_123', {'title' => 'New Task', 'status' => 'Active'})
      #   # => { success: true, id: "rec_123", title: "New Task", operation: "create",
      #          timestamp: "2025-11-19T...", cached: true }
      # @example Full response (for backward compatibility)
      #   create_record('tbl_123', {'title' => 'New Task'}, minimal_response: false)
      #   # => { id: "rec_123", title: "New Task", status: "Active", ... 50+ fields }
      def create_record(table_id, data, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('data', data, Hash)

        response = api_request(:post, "/applications/#{table_id}/records/", data)

        if minimal_response
          # Smart cache coordination: Update cache with full response
          @cache&.cache_single_record(table_id, response)

          # Return minimal response (95% token reduction)
          build_minimal_response(
            operation: 'create',
            record_id: response['id'],
            title: response['title'],
            cached: @cache ? true : false
          )
        else
          format_single_response(response, format)
        end
      end

      # Updates an existing record.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier
      # @param data [Hash] Record data to update as field_slug => value pairs
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~95% token reduction) and updates cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Hash, String] Updated record data (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example Minimal response (default, 95% token savings)
      #   update_record('tbl_123', 'rec_abc', {'status' => 'Completed'})
      #   # => { success: true, id: "rec_abc", title: "Task", operation: "update",
      #          timestamp: "2025-11-19T...", cached: true }
      # @example Full response (for backward compatibility)
      #   update_record('tbl_123', 'rec_abc', {'status' => 'Completed'}, minimal_response: false)
      #   # => { id: "rec_abc", title: "Task", status: "Completed", ... 50+ fields }
      def update_record(table_id, record_id, data, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)
        validate_required_parameter!('data', data, Hash)

        response = api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)

        if minimal_response
          # Smart cache coordination: Update cache with full response
          @cache&.cache_single_record(table_id, response)

          # Return minimal response (95% token reduction)
          build_minimal_response(
            operation: 'update',
            record_id: response['id'],
            title: response['title'],
            cached: @cache ? true : false
          )
        else
          format_single_response(response, format)
        end
      end

      # Deletes a record from a table.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to delete
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~80% token reduction) and removes from cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Hash, String] Deletion confirmation (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing
      # @example Minimal response (default, 80% token savings)
      #   delete_record('tbl_123', 'rec_abc')
      #   # => { success: true, id: "rec_abc", operation: "delete",
      #          timestamp: "2025-11-19T...", cached: false }
      # @example Full response (for backward compatibility)
      #   delete_record('tbl_123', 'rec_abc', minimal_response: false)
      #   # => { success: true, message: "Record deleted", ... }
      def delete_record(table_id, record_id, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        response = api_request(:delete, "/applications/#{table_id}/records/#{record_id}/")

        if minimal_response
          # Smart cache coordination: Remove record from cache
          @cache&.delete_cached_record(table_id, record_id)

          # Return minimal response (80% token reduction)
          build_minimal_response(
            operation: 'delete',
            record_id: record_id,
            cached: false
          )
        else
          format_single_response(response, format)
        end
      end

      # Creates multiple records in a single request (bulk operation).
      #
      # More efficient than multiple create_record calls when adding many records.
      # Accepts an array of record data hashes.
      #
      # @param table_id [String] Table identifier
      # @param records [Array<Hash>] Array of record data hashes (field_slug => value)
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~90% token reduction) and updates cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Array<Hash>, String] Array of created records (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example Minimal response (default, 90% token savings)
      #   bulk_add_records('tbl_123', [
      #     {'title' => 'Task 1', 'status' => 'Active'},
      #     {'title' => 'Task 2', 'status' => 'Pending'}
      #   ])
      #   # => [
      #     { success: true, id: "rec_123", title: "Task 1", operation: "bulk_create", ... },
      #     { success: true, id: "rec_124", title: "Task 2", operation: "bulk_create", ... }
      #   ]
      # @example Full response (for backward compatibility)
      #   bulk_add_records('tbl_123', [...], minimal_response: false)
      def bulk_add_records(table_id, records, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('records', records, Array)

        response = api_request(:post, "/applications/#{table_id}/records/bulk/", { 'items' => records })

        if minimal_response
          # Smart cache coordination: Cache all created records
          response.each { |record| @cache&.cache_single_record(table_id, record) } if response.is_a?(Array)

          # Return minimal response (90% token reduction)
          if response.is_a?(Array)
            response.map do |record|
              build_minimal_response(
                operation: 'bulk_create',
                record_id: record['id'],
                title: record['title'],
                cached: @cache ? true : false
              )
            end
          else
            response # Fallback if response format unexpected
          end
        else
          format_array_response(response, format, 'records')
        end
      end

      # Updates multiple records in a single request (bulk operation).
      #
      # More efficient than multiple update_record calls when updating many records.
      # Each record hash must include 'id' field along with fields to update.
      #
      # @param table_id [String] Table identifier
      # @param records [Array<Hash>] Array of record hashes with 'id' and fields to update
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~90% token reduction) and updates cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Array<Hash>, String] Array of updated records (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example Minimal response (default, 90% token savings)
      #   bulk_update_records('tbl_123', [
      #     {'id' => 'rec_abc', 'status' => 'Completed'},
      #     {'id' => 'rec_def', 'status' => 'In Progress'}
      #   ])
      #   # => [
      #     { success: true, id: "rec_abc", title: "Task", operation: "bulk_update", ... },
      #     { success: true, id: "rec_def", title: "Task", operation: "bulk_update", ... }
      #   ]
      # @example Full response (for backward compatibility)
      #   bulk_update_records('tbl_123', [...], minimal_response: false)
      def bulk_update_records(table_id, records, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('records', records, Array)

        response = api_request(:patch, "/applications/#{table_id}/records/bulk/", { 'items' => records })

        if minimal_response
          # Smart cache coordination: Update all records in cache
          response.each { |record| @cache&.cache_single_record(table_id, record) } if response.is_a?(Array)

          # Return minimal response (90% token reduction)
          if response.is_a?(Array)
            response.map do |record|
              build_minimal_response(
                operation: 'bulk_update',
                record_id: record['id'],
                title: record['title'],
                cached: @cache ? true : false
              )
            end
          else
            response # Fallback if response format unexpected
          end
        else
          format_array_response(response, format, 'records')
        end
      end

      # Deletes multiple records in a single request (bulk operation).
      #
      # More efficient than multiple delete_record calls when deleting many records.
      # This performs a soft delete - records can be restored using restore_deleted_record.
      #
      # @param table_id [String] Table identifier
      # @param record_ids [Array<String>] Array of record IDs to delete
      # @param minimal_response [Boolean] Return minimal response (default: true)
      #   When true, returns only essential fields (~80% token reduction) and removes from cache
      #   Set to false for backward compatibility or when full response needed
      # @param format [Symbol] Output format: :toon (default) or :json (only used when minimal_response: false)
      # @return [Hash, String] Deletion confirmation (minimal or full based on parameter)
      # @raise [ArgumentError] If required parameters are missing or invalid
      # @example Minimal response (default, 80% token savings)
      #   bulk_delete_records('tbl_123', ['rec_abc', 'rec_def', 'rec_ghi'])
      #   # => { success: true, deleted_count: 3, operation: "bulk_delete",
      #          timestamp: "2025-11-19T...", cached: false }
      # @example Full response (for backward compatibility)
      #   bulk_delete_records('tbl_123', [...], minimal_response: false)
      def bulk_delete_records(table_id, record_ids, minimal_response: true, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_ids', record_ids, Array)

        response = api_request(:patch, "/applications/#{table_id}/records/bulk_delete/", { 'items' => record_ids })

        if minimal_response
          # Smart cache coordination: Remove all deleted records from cache
          record_ids.each { |record_id| @cache&.delete_cached_record(table_id, record_id) }

          # Return minimal response (80% token reduction)
          {
            'success' => true,
            'deleted_count' => record_ids.length,
            'operation' => 'bulk_delete',
            'timestamp' => Time.now.utc.iso8601,
            'cached' => false # Records removed from cache
          }
        else
          format_single_response(response, format)
        end
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
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Array<Hash>] TOON string or JSON array depending on format
      # @raise [ArgumentError] If solution_id is missing
      # @example
      #   list_deleted_records('sol_123', preview: true)
      #   list_deleted_records('sol_123', format: :json)
      def list_deleted_records(solution_id, preview: true, format: :toon)
        validate_required_parameter!('solution_id', solution_id)

        # Build endpoint with query parameter
        endpoint = build_endpoint('/deleted-records/', preview: preview)

        # Body contains solution_id
        body = { solution_id: solution_id }

        response = api_request(:post, endpoint, body)

        return response unless response.is_a?(Array)

        format_deleted_records_output(response, format)
      end

      # Format deleted records output based on format parameter
      #
      # @param records [Array<Hash>] Deleted records data
      # @param format [Symbol] Output format (:toon or :json)
      # @return [String, Array<Hash>] Formatted output
      def format_deleted_records_output(records, format)
        case format
        when :toon
          SmartSuite::Formatters::ToonFormatter.format(records)
        else # :json
          records
        end
      end

      # Restores a deleted record.
      #
      # Restores a soft-deleted record back to the table.
      # The restored record will have "(Restored)" appended to its title.
      #
      # @param table_id [String] Table identifier
      # @param record_id [String] Record identifier to restore
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Restored record data in requested format
      # @raise [ArgumentError] If required parameters are missing
      # @example
      #   restore_deleted_record('tbl_123', 'rec_abc')
      def restore_deleted_record(table_id, record_id, format: :toon)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)

        response = api_request(:post, "/applications/#{table_id}/records/#{record_id}/restore/", {})
        format_single_response(response, format)
      end

      # Attach files to a record by URL or local file path.
      #
      # Automatically detects whether inputs are URLs or local file paths:
      # - URLs: Passed directly to SmartSuite API for download
      # - Local files: Uploaded to S3 first, then attached via temporary URLs
      #
      # @param table_id [String] the ID of the table containing the record
      # @param record_id [String] the ID of the record to attach the file to
      # @param file_field_slug [String] the slug of the file/image field
      # @param file_urls [Array<String>] array of URLs or local file paths to attach
      # @return [Hash] the updated record object
      # @raise [ArgumentError] if required parameters are missing or S3 not configured for local files
      # @raise [RuntimeError] if the API request fails
      #
      # @example Attach files by URL
      #   attach_file('tbl_123', 'rec_456', 'attachments', ['https://example.com/file.pdf'])
      #
      # @example Attach local files (requires S3 configuration)
      #   attach_file('tbl_123', 'rec_456', 'attachments', ['/path/to/local/file.pdf'])
      #
      # @example Mix of URLs and local files
      #   attach_file('tbl_123', 'rec_456', 'images', [
      #     'https://example.com/image1.jpg',
      #     '/local/path/image2.jpg'
      #   ])
      #
      # @note For local files, requires environment variables:
      #   - SMARTSUITE_S3_BUCKET: S3 bucket name for temporary uploads
      #   - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (or IAM role)
      #   - AWS_REGION (optional, defaults to us-east-1)
      def attach_file(table_id, record_id, file_field_slug, file_urls)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)
        validate_required_parameter!('file_field_slug', file_field_slug)
        validate_required_parameter!('file_urls', file_urls, Array)

        # Separate local files from URLs
        local_files, urls = partition_files_and_urls(file_urls)

        # Validate we have something to attach
        raise ArgumentError, 'file_urls array is empty or contains no valid files/URLs' if local_files.empty? && urls.empty?

        results = []

        # Handle local files via SecureFileAttacher
        if local_files.any?
          result = attach_local_files(table_id, record_id, file_field_slug, local_files)
          results << { 'type' => 'local', 'files' => local_files.map { |f| File.basename(f) }, 'result' => result }
        end

        # Handle URLs directly via API
        if urls.any?
          result = attach_urls(table_id, record_id, file_field_slug, urls)
          results << { 'type' => 'url', 'files' => urls, 'result' => result }
        end

        # Return combined status
        {
          'success' => true,
          'record_id' => record_id,
          'attached_count' => local_files.length + urls.length,
          'local_files' => local_files.length,
          'url_files' => urls.length,
          'details' => results
        }
      end

      private

      # Partition input into local file paths and URLs
      #
      # @param inputs [Array<String>] mixed array of file paths and URLs
      # @return [Array<Array<String>, Array<String>>] [local_files, urls]
      def partition_files_and_urls(inputs)
        local_files = []
        urls = []

        inputs.each do |input|
          if url?(input)
            urls << input
          else
            local_files << input
          end
        end

        [local_files, urls]
      end

      # Check if a string is a URL
      #
      # @param str [String] string to check
      # @return [Boolean] true if string looks like a URL
      def url?(str)
        str.start_with?('http://', 'https://')
      end

      # Attach local files using SecureFileAttacher
      #
      # @param table_id [String] table ID
      # @param record_id [String] record ID
      # @param field_slug [String] file field slug
      # @param local_files [Array<String>] local file paths
      # @return [Hash] API response
      def attach_local_files(table_id, record_id, field_slug, local_files)
        bucket_name = ENV.fetch('SMARTSUITE_S3_BUCKET', nil)
        aws_profile = ENV.fetch('SMARTSUITE_AWS_PROFILE', nil)
        has_aws_env_creds = ENV.fetch('AWS_ACCESS_KEY_ID', nil) && ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)

        # Check for missing S3 bucket
        unless bucket_name
          raise ArgumentError, <<~ERROR
            Local file attachment requires S3 configuration.

            Missing: SMARTSUITE_S3_BUCKET environment variable

            Current settings detected:
              SMARTSUITE_S3_BUCKET: (not set)
              SMARTSUITE_AWS_PROFILE: #{aws_profile || '(not set)'}
              AWS_ACCESS_KEY_ID: #{ENV['AWS_ACCESS_KEY_ID'] ? '(set)' : '(not set)'}
              AWS_REGION: #{ENV.fetch('AWS_REGION', '(not set, will use us-east-1)')}

            Required setup:
              export SMARTSUITE_S3_BUCKET=your-bucket-name
              export SMARTSUITE_AWS_PROFILE=your-profile-name
              export AWS_REGION=your-region

            Alternatively, provide publicly accessible URLs instead of local file paths.
          ERROR
        end

        # Check for missing AWS credentials
        unless aws_profile || has_aws_env_creds
          raise ArgumentError, <<~ERROR
            Local file attachment requires AWS credentials.

            Missing: AWS credentials (no profile or access keys found)

            Current settings detected:
              SMARTSUITE_S3_BUCKET: #{bucket_name}
              SMARTSUITE_AWS_PROFILE: (not set)
              AWS_ACCESS_KEY_ID: (not set)
              AWS_REGION: #{ENV.fetch('AWS_REGION', '(not set, will use us-east-1)')}

            Set one of:
              Option 1 - Named profile (recommended):
                export SMARTSUITE_AWS_PROFILE=your-profile-name
                (configure profile in ~/.aws/credentials)

              Option 2 - Environment variables:
                export AWS_ACCESS_KEY_ID=your-access-key
                export AWS_SECRET_ACCESS_KEY=your-secret-key

            Alternatively, provide publicly accessible URLs instead of local file paths.
          ERROR
        end

        # Lazy-load SecureFileAttacher to avoid aws-sdk-s3 dependency when not needed
        require_relative '../../secure_file_attacher'

        # Build S3 options - use dedicated profile if specified
        s3_options = { region: ENV.fetch('AWS_REGION', 'us-east-1') }
        s3_options[:profile] = aws_profile if aws_profile

        attacher = SecureFileAttacher.new(
          self,
          bucket_name,
          **s3_options
        )

        attacher.attach_file_securely(table_id, record_id, field_slug, local_files)
      end

      # Attach files by URL directly via API
      #
      # @param table_id [String] table ID
      # @param record_id [String] record ID
      # @param field_slug [String] file field slug
      # @param urls [Array<String>] file URLs
      # @return [Hash] API response
      def attach_urls(table_id, record_id, field_slug, urls)
        body = {
          'id' => record_id,
          field_slug => urls
        }

        api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", body)
      end

      # Builds a minimal response hash for mutation operations.
      #
      # This helper method provides a consistent minimal response format across
      # all create/update/delete operations, eliminating code duplication.
      #
      # @param operation [String] The operation type: 'create', 'update', or 'delete'
      # @param record_id [String] The record ID
      # @param title [String, nil] The record title (optional, defaults to record_id)
      # @param cached [Boolean] Whether the record is cached (true for create/update, false for delete)
      # @return [Hash] Minimal response with success, id, title, operation, timestamp, and cached status
      # @api private
      def build_minimal_response(operation:, record_id:, title: nil, cached: true)
        {
          'success' => true,
          'id' => record_id,
          'title' => title || record_id,
          'operation' => operation,
          'timestamp' => Time.now.utc.iso8601,
          'cached' => cached
        }
      end
    end
  end
end
