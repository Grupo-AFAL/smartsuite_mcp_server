# frozen_string_literal: true

require_relative "toon_formatter"
require_relative "../date_formatter"

module SmartSuite
  # Response formatting module
  #
  # Contains formatters for optimizing API responses to minimize token usage.
  # Implements aggressive filtering and TOON formatting strategies.
  module Formatters
    # ResponseFormatter handles aggressive response filtering to minimize token usage.
    #
    # This module implements the core token optimization strategy:
    # - Filters table field structures (saves ~80% tokens)
    # - Filters record responses and formats as TOON (saves ~50-60% tokens)
    # - Generates summary statistics instead of full data
    # - Processes SmartDoc fields to extract only HTML content
    # - Estimates token usage for logging
    #
    # All methods prioritize minimizing Claude's context window consumption.
    module ResponseFormatter
      # Filters a field definition to only essential information.
      #
      # Removes UI/display metadata while keeping functional field data.
      # Achieves ~83.8% token reduction on table structures.
      #
      # Also adds hints for fields that typically contain large amounts of data,
      # helping AI be more selective about which fields to request.
      #
      # @param field [Hash] Raw field definition from API
      # @return [Hash] Filtered field with only slug, label, type, and essential params
      def filter_field_structure(field)
        # Extract only essential field information
        filtered = {
          "slug" => field["slug"],
          "label" => field["label"],
          "field_type" => field["field_type"]
        }

        # Add warning for fields that typically contain large content
        if large_content_field?(field["field_type"])
          filtered["large_content_warning"] = "This field may contain extensive data (10K+ tokens). Request only when needed."
        end

        # Only include essential params if params exist
        return filtered unless field["params"]

        params = {}

        # Always include these if present
        params["primary"] = true if field["params"]["primary"]
        params["required"] = field["params"]["required"] unless field["params"]["required"].nil?
        params["unique"] = field["params"]["unique"] unless field["params"]["unique"].nil?

        # For choice fields (status, single select, multi select), strip down choices to only label and value
        if field["params"]["choices"]
          params["choices"] = field["params"]["choices"].map do |choice|
            { "label" => choice["label"], "value" => choice["value"] }
          end
        end

        # For linked record fields, include target table and cardinality
        if field["params"]["linked_application"]
          params["linked_application"] = field["params"]["linked_application"]
          params["entries_allowed"] = field["params"]["entries_allowed"] if field["params"]["entries_allowed"]
        end

        filtered["params"] = params unless params.empty?
        filtered
      end

      # Determines if a field type typically contains large amounts of data.
      #
      # These fields should be requested selectively to avoid token limits.
      #
      # @param field_type [String] SmartSuite field type
      # @return [Boolean] True if field typically contains large content
      def large_content_field?(field_type)
        return false unless field_type

        large_types = %w[
          textarea
          richtextarea
          comments
          files
        ]

        large_types.include?(field_type.downcase)
      end

      # Filters and formats record list responses for minimal token usage.
      #
      # Applies field filtering, converts to optimized format (saves ~50-60% tokens vs JSON),
      # and logs token reduction metrics. Always includes total vs filtered record counts.
      #
      # Supports two output formats:
      # - TOON (default): Token-Oriented Object Notation (~50-60% savings)
      # - JSON: Standard JSON output
      #
      # @param response [Hash] Raw API response with 'items' array
      # @param fields [Array<String>, nil] Field slugs to include
      # @param toon [Boolean] Format as TOON for maximum token savings (default: false)
      # @param hydrated [Boolean] Whether response includes hydrated values (informational only)
      # @return [String, Hash] Formatted string (toon) or filtered JSON hash
      def filter_records_response(response, fields, toon: false, hydrated: true)
        return response unless response.is_a?(Hash) && response["items"].is_a?(Array)

        original_tokens = estimate_tokens(JSON.generate(response))
        filtered_items = filter_items(response["items"], fields)
        filtered_count = response["filtered_count"] || response["total_count"]
        warnings = response["warnings"] || []

        if toon
          format_as_toon_response(filtered_items, response, original_tokens, filtered_count, warnings)
        else
          format_as_json_response(filtered_items, response, original_tokens, warnings)
        end
      end

      private

      # Filter items based on requested fields
      def filter_items(items, fields)
        # Ensure fields is an array (may arrive as JSON string from some MCP clients)
        fields = JSON.parse(fields) if fields.is_a?(String) rescue fields
        items.map do |record|
          requested_fields = fields.is_a?(Array) && fields.any? ? (fields + %w[id title]).uniq : %w[id title]
          filter_record_fields(record, requested_fields)
        end
      end

      # Format response as TOON
      def format_as_toon_response(items, response, original_tokens, filtered_count, warnings = [])
        result = ToonFormatter.format_records(items, total_count: response["total_count"], filtered_count: filtered_count)
        # Prepend warnings to the result if any
        result = format_warnings_prefix(warnings) + result if warnings.any?
        log_format_metrics(items.size, response["total_count"], filtered_count, original_tokens, result, "TOON")
        result
      end

      # Format response as JSON
      def format_as_json_response(items, response, _original_tokens, warnings = [])
        result = { "items" => items, "total_count" => response["total_count"], "count" => items.size }
        result["warnings"] = warnings if warnings.any?
        tokens = estimate_tokens(JSON.generate(result))
        total_tokens = update_token_usage(tokens)
        total_records = response["total_count"] || items.size
        log_metric("✓ #{items.size} of #{total_records} records | +#{tokens} tokens (Total: #{total_tokens})")
        result
      end

      # Format warnings as a prefix string
      def format_warnings_prefix(warnings)
        return "" if warnings.empty?

        header = "⚠️  FILTER WARNINGS:\n"
        warning_lines = warnings.map { |w| "  • #{w}" }.join("\n")
        "#{header}#{warning_lines}\n\n"
      end

      # Log format metrics consistently
      def log_format_metrics(count, total, filtered, _original_tokens, result, _format_name)
        tokens = estimate_tokens(result)
        total_tokens = update_token_usage(tokens)
        record_msg = if filtered && filtered < total
                       "#{count} of #{filtered} records (#{total} in table)"
        else
                       "#{count} of #{total} records"
        end
        log_metric("✓ #{record_msg} | +#{tokens} tokens (Total: #{total_tokens})")
      end

      public

      # Estimates token count for text.
      #
      # Uses 1.5 characters per token heuristic, which tends to overestimate
      # (safer than underestimating). Optimized for JSON structure estimation.
      #
      # @param text [String] Text to estimate
      # @return [Integer] Estimated token count
      def estimate_tokens(text)
        # More accurate approximation for JSON:
        # - Each character is ~1 token due to structure (brackets, quotes, commas)
        # - Using 1.5 chars per token is more realistic for JSON
        # This tends to OVERESTIMATE slightly, which is safer than underestimating
        (text.length / 1.5).round
      end

      # Generates statistical summary of records instead of full data.
      #
      # Analyzes field values and returns counts/distributions. Minimizes
      # token usage for overview/exploration purposes.
      #
      # @param response [Hash] Raw API response with 'items' array
      # @return [Hash] Summary with statistics and field analysis
      def generate_summary(response)
        return response unless response.is_a?(Hash) && response["items"].is_a?(Array)

        items = response["items"]
        total = response["total_count"] || items.size

        # Collect field statistics
        field_stats = {}

        items.each do |record|
          record.each do |key, value|
            next if %w[id application_id first_created last_updated autonumber].include?(key)

            field_stats[key] ||= {}

            # Count values for this field
            value_key = value.to_s[0...50] # Truncate long values
            field_stats[key][value_key] ||= 0
            field_stats[key][value_key] += 1
          end
        end

        # Build summary text
        summary_lines = [ "Found #{items.size} records (total: #{total})" ]

        field_stats.each do |field, values|
          if values.size <= 10
            value_summary = values.map { |v, count| "#{v} (#{count})" }.join(", ")
            summary_lines << "  #{field}: #{value_summary}"
          else
            summary_lines << "  #{field}: #{values.size} unique values"
          end
        end

        result = {
          summary: summary_lines.join("\n"),
          count: items.size,
          total_count: total,
          fields_analyzed: field_stats.keys
        }

        tokens = estimate_tokens(JSON.generate(result))
        total_tokens = update_token_usage(tokens)
        log_metric("✓ #{items.size} records (summary) | +#{tokens} tokens (Total: #{total_tokens})")

        result
      end

      # Filters a record to only include specified fields.
      #
      # Applies truncation to field values to minimize token usage.
      #
      # @param record [Hash] Complete record data
      # @param include_fields [Array<String>] Field slugs to include
      # @return [Hash] Filtered record with only specified fields
      def filter_record_fields(record, include_fields)
        return record unless record.is_a?(Hash)

        # Only include specified fields
        result = {}
        include_fields.each do |field|
          result[field] = truncate_value(record[field]) if record.key?(field)
        end
        result
      end

      # Processes field values for AI consumption.
      #
      # Applies several transformations:
      # 1. SmartDoc fields: extracts only HTML content to minimize tokens
      # 2. Timestamps: converts UTC dates to local time for user readability
      # 3. Complex JSON structures: recursively converts nested timestamps
      #
      # Cache stores the complete JSON structure as JSON strings, so we parse them first.
      #
      # @param value [Object] Field value
      # @return [Object] Processed value (HTML for SmartDoc, local time for timestamps)
      def truncate_value(value)
        # Try to parse JSON strings (cache stores complex values as JSON)
        parsed_value = value.is_a?(String) ? parse_json_safe(value) : value

        # Detect SmartDoc structure (has data, html, preview, yjsData keys)
        if smartdoc_value?(parsed_value)
          # Return only HTML content for AI
          # Cache still stores complete JSON with all keys
          parsed_value["html"] || parsed_value[:html] || ""
        elsif parsed_value.is_a?(Hash) || parsed_value.is_a?(Array)
          # Complex structure - recursively convert timestamps
          DateFormatter.convert_all(parsed_value)
        elsif value.is_a?(String) && DateFormatter.timestamp?(value)
          # Simple timestamp string - convert to local time
          DateFormatter.to_local(value)
        else
          value # Return original value
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
      # SmartDoc fields contain rich text with structure:
      # - data: TipTap/ProseMirror document structure
      # - html: Rendered HTML content
      # - preview: Plain text preview
      # - yjsData: Collaborative editing data
      #
      # @param value [Object] Field value to check
      # @return [Boolean] True if value is a SmartDoc structure
      def smartdoc_value?(value)
        return false unless value.is_a?(Hash)

        # Check for SmartDoc signature keys
        has_data = value.key?("data") || value.key?(:data)
        has_html = value.key?("html") || value.key?(:html)

        has_data && has_html
      end
    end
  end
end
