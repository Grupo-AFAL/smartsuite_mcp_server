module SmartSuite
  module API
    # RecordOperations handles CRUD operations on table records.
    #
    # This module provides methods for:
    # - Listing records with filtering, sorting, and pagination
    # - Getting individual records
    # - Creating, updating, and deleting records
    #
    # Implements aggressive validation and filtering to minimize token usage.
    module RecordOperations
      # Lists records from a table with filtering, sorting, and field selection.
      #
      # IMPORTANT: Requires either `fields` parameter or `summary_only: true` to
      # prevent excessive context usage. Without filters, automatically limits to
      # 2 records.
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
      # @return [String, Hash] Plain text formatted records or summary hash
      def list_records(table_id, limit = nil, offset = 0, filter: nil, sort: nil, fields: nil, summary_only: false, full_content: false)
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

        # Build query params for limit and offset
        query_params = "?limit=#{limit}&offset=#{offset}"

        # Build body with filter and sort (if provided)
        body = {}

        # Add filter if provided
        # Filter format: {"operator": "and|or", "fields": [{"field": "field_slug", "comparison": "operator", "value": "value"}]}
        # Example: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}
        body[:filter] = filter if filter

        # Add sort if provided
        # Sort format: [{"field": "field_slug", "direction": "asc|desc"}]
        # Example: [{"field": "created_on", "direction": "desc"}]
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
