# frozen_string_literal: true

require_relative 'base'

module SmartSuite
  module API
    # CommentOperations handles comment-related API calls.
    #
    # Comments are associated with records and support rich text formatting.
    # Uses Base module for common API patterns (validation, endpoint building).
    module CommentOperations
      include Base

      # List all comments for a specific record.
      #
      # @param record_id [String] The ID of the record
      # @return [Hash] API response containing array of comment objects with accurate count
      # @raise [ArgumentError] If record_id is nil or empty
      # @raise [RuntimeError] If the API request fails
      # @example
      #   list_comments("rec_abc123")
      def list_comments(record_id)
        validate_required_parameter!('record_id', record_id)

        endpoint = build_endpoint('/comments/', record: record_id)
        response = api_request(:get, endpoint)

        # SmartSuite API returns count: null, so calculate from results
        response['count'] = response['results'].length if response.is_a?(Hash) && response['results'].is_a?(Array)

        response
      end

      # Add a comment to a record.
      #
      # Automatically converts plain text messages to SmartSuite's rich text format (TipTap/ProseMirror).
      #
      # @param table_id [String] The ID of the table/application
      # @param record_id [String] The ID of the record
      # @param message [String] The comment text (plain text will be converted to rich text format)
      # @param assigned_to [String, nil] Optional user ID to assign the comment to
      # @return [Hash] API response containing the created comment object
      # @raise [ArgumentError] If required parameters are nil or empty
      # @raise [RuntimeError] If the API request fails
      # @example Basic usage
      #   add_comment("tbl_123", "rec_456", "This is a comment")
      #
      # @example With assignment
      #   add_comment("tbl_123", "rec_456", "Review needed", "user_789")
      def add_comment(table_id, record_id, message, assigned_to = nil)
        validate_required_parameter!('table_id', table_id)
        validate_required_parameter!('record_id', record_id)
        validate_required_parameter!('message', message)

        body = {
          'assigned_to' => assigned_to,
          'message' => format_message(message),
          'application' => table_id,
          'record' => record_id
        }

        api_request(:post, '/comments/', body)
      end

      private

      # Format plain text message into SmartSuite's rich text format (TipTap/ProseMirror)
      # SmartSuite uses a document structure with content blocks
      #
      # @param text [String] Plain text message
      # @return [Hash] Formatted message object
      def format_message(text)
        {
          'data' => {
            'type' => 'doc',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => [
                  {
                    'type' => 'text',
                    'text' => text
                  }
                ]
              }
            ]
          }
        }
      end
    end
  end
end
