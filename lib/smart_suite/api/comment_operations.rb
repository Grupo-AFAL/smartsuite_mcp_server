# frozen_string_literal: true

require_relative "base"
require_relative "../formatters/toon_formatter"

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
      # @param format [Symbol] Output format: :toon (default, ~50-60% savings) or :json
      # @return [String, Hash] TOON string or JSON hash depending on format
      # @raise [ArgumentError] If record_id is nil or empty
      # @raise [RuntimeError] If the API request fails
      # @example
      #   list_comments("rec_abc123")
      #   list_comments("rec_abc123", format: :json)
      def list_comments(record_id, format: :toon)
        validate_required_parameter!("record_id", record_id)

        endpoint = build_endpoint("/comments/", record: record_id)
        response = api_request(:get, endpoint)

        return response unless response.is_a?(Hash) && response["results"].is_a?(Array)

        # SmartSuite API returns count: null, so calculate from results
        comments = response["results"]
        count = comments.length

        format_comments_output(comments, count, format)
      end

      # Add a comment to a record.
      #
      # Automatically converts plain text messages to SmartSuite's rich text format (TipTap/ProseMirror).
      #
      # @param table_id [String] The ID of the table/application
      # @param record_id [String] The ID of the record
      # @param message [String] The comment text (plain text will be converted to rich text format)
      # @param assigned_to [String, nil] Optional user ID to assign the comment to
      # @param format [Symbol] Output format: :toon (default) or :json
      # @return [String, Hash] Created comment in requested format
      # @raise [ArgumentError] If required parameters are nil or empty
      # @raise [RuntimeError] If the API request fails
      # @example Basic usage
      #   add_comment("tbl_123", "rec_456", "This is a comment")
      #
      # @example With assignment
      #   add_comment("tbl_123", "rec_456", "Review needed", "user_789")
      def add_comment(table_id, record_id, message, assigned_to = nil, format: :toon)
        validate_required_parameter!("table_id", table_id)
        validate_required_parameter!("record_id", record_id)
        validate_required_parameter!("message", message)

        body = {
          "assigned_to" => assigned_to,
          "message" => format_message(message),
          "application" => table_id,
          "record" => record_id
        }

        response = api_request(:post, "/comments/", body)
        format_single_response(response, format)
      end

      private

      # Format comments output based on format parameter
      #
      # @param comments [Array<Hash>] Comments data
      # @param count [Integer] Number of comments
      # @param format [Symbol] Output format (:toon or :json)
      # @return [String, Hash] Formatted output
      def format_comments_output(comments, count, format)
        case format
        when :toon
          SmartSuite::Formatters::ToonFormatter.format(comments)
        else # :json
          { "results" => comments, "count" => count }
        end
      end

      # Format plain text message into SmartSuite's rich text format (TipTap/ProseMirror)
      # SmartSuite uses a document structure with content blocks
      #
      # @param text [String] Plain text message
      # @return [Hash] Formatted message object
      def format_message(text)
        {
          "data" => {
            "type" => "doc",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [
                  {
                    "type" => "text",
                    "text" => text
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
