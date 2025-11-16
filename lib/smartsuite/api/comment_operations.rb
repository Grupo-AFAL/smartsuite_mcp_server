# frozen_string_literal: true

module SmartSuite
  module API
    # CommentOperations handles comment-related API calls
    # Comments are associated with records and support rich text formatting
    module CommentOperations
      # List all comments for a specific record
      #
      # @param record_id [String] The ID of the record
      # @return [Hash] API response containing array of comment objects
      # @raise [RuntimeError] If the API request fails
      #
      # GET /api/v1/comments/?record=[Record_Id]
      def list_comments(record_id)
        raise ArgumentError, 'record_id is required' if record_id.nil? || record_id.empty?

        endpoint = "/comments/?record=#{record_id}"
        api_request(:get, endpoint)
      end

      # Add a comment to a record
      #
      # @param table_id [String] The ID of the table/application
      # @param record_id [String] The ID of the record
      # @param message [String] The comment text (plain text will be converted to rich text format)
      # @param assigned_to [String, nil] Optional user ID to assign the comment to
      # @return [Hash] API response containing the created comment object
      # @raise [RuntimeError] If the API request fails
      #
      # POST /api/v1/comments/
      #
      # Example:
      #   add_comment("app123", "rec456", "This is a comment", nil)
      #   add_comment("app123", "rec456", "Review needed", "user789")
      def add_comment(table_id, record_id, message, assigned_to = nil)
        raise ArgumentError, 'table_id is required' if table_id.nil? || table_id.empty?
        raise ArgumentError, 'record_id is required' if record_id.nil? || record_id.empty?
        raise ArgumentError, 'message is required' if message.nil? || message.empty?

        endpoint = '/comments/'
        body = {
          'assigned_to' => assigned_to,
          'message' => format_message(message),
          'application' => table_id,
          'record' => record_id
        }

        api_request(:post, endpoint, body)
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
