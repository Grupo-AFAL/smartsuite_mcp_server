module SmartSuite
  module Formatters
    # ResponseFormatter handles aggressive response filtering to minimize token usage.
    #
    # This module implements the core token optimization strategy:
    # - Filters table field structures (saves ~80% tokens)
    # - Filters record responses and formats as plain text (saves ~40% tokens)
    # - Generates summary statistics instead of full data
    # - Truncates long field values
    # - Estimates token usage for logging
    #
    # All methods prioritize minimizing Claude's context window consumption.
    module ResponseFormatter
      # Filters a field definition to only essential information.
      #
      # Removes UI/display metadata while keeping functional field data.
      # Achieves ~83.8% token reduction on table structures.
      #
      # @param field [Hash] Raw field definition from API
      # @return [Hash] Filtered field with only slug, label, type, and essential params
      def filter_field_structure(field)
        # Extract only essential field information
        filtered = {
          'slug' => field['slug'],
          'label' => field['label'],
          'field_type' => field['field_type']
        }

        # Only include essential params if params exist
        return filtered unless field['params']

        params = {}

        # Always include these if present
        params['primary'] = true if field['params']['primary']
        params['required'] = field['params']['required'] unless field['params']['required'].nil?
        params['unique'] = field['params']['unique'] unless field['params']['unique'].nil?

        # For choice fields (status, single select, multi select), strip down choices to only label and value
        if field['params']['choices']
          params['choices'] = field['params']['choices'].map do |choice|
            {'label' => choice['label'], 'value' => choice['value']}
          end
        end

        # For linked record fields, include target table and cardinality
        if field['params']['linked_application']
          params['linked_application'] = field['params']['linked_application']
          params['entries_allowed'] = field['params']['entries_allowed'] if field['params']['entries_allowed']
        end

        filtered['params'] = params unless params.empty?
        filtered
      end

      # Filters and formats record list responses for minimal token usage.
      #
      # Applies field filtering, optionally converts to plain text format
      # (saves ~40% tokens vs JSON), and logs token reduction metrics.
      #
      # @param response [Hash] Raw API response with 'items' array
      # @param fields [Array<String>, nil] Field slugs to include
      # @param plain_text [Boolean] Format as plain text instead of JSON (default: false)
      # @param full_content [Boolean] Skip value truncation (default: false)
      # @return [String, Hash] Plain text string or filtered JSON hash
      def filter_records_response(response, fields, plain_text: false, full_content: false)
        return response unless response.is_a?(Hash) && response['items'].is_a?(Array)

        # Calculate original size in tokens (approximate)
        original_json = JSON.generate(response)
        original_tokens = estimate_tokens(original_json)

        filtered_items = response['items'].map do |record|
          if fields && !fields.empty?
            # If specific fields requested, only return those + id/title
            requested_fields = (fields + ['id', 'title']).uniq
            filter_record_fields(record, requested_fields, full_content: full_content)
          else
            # Default: only id and title (minimal context usage)
            filter_record_fields(record, ['id', 'title'], full_content: full_content)
          end
        end

        # Format as plain text to save ~40% tokens vs JSON
        if plain_text
          result_text = format_as_plain_text(filtered_items, response['total_count'], full_content: full_content)
          tokens = estimate_tokens(result_text)
          reduction_percent = ((original_tokens - tokens).to_f / original_tokens * 100).round(1)

          content_mode = full_content ? "full content" : "truncated"
          log_metric("✓ Found #{filtered_items.size} records (plain text, #{content_mode})")
          log_metric("📊 #{original_tokens} → #{tokens} tokens (saved #{reduction_percent}%)")
          log_token_usage(tokens)

          return result_text
        end

        # JSON format (for backward compatibility)
        result = {
          'items' => filtered_items,
          'total_count' => response['total_count'],
          'count' => filtered_items.size
        }

        # Calculate filtered size in tokens and log reduction
        filtered_json = JSON.generate(result)
        filtered_tokens = estimate_tokens(filtered_json)
        reduction_percent = ((original_tokens - filtered_tokens).to_f / original_tokens * 100).round(1)

        log_metric("✓ Found #{result['count']} records")
        log_metric("📊 #{original_tokens} → #{filtered_tokens} tokens (saved #{reduction_percent}%)")
        log_token_usage(filtered_tokens)

        result
      end

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
        return response unless response.is_a?(Hash) && response['items'].is_a?(Array)

        items = response['items']
        total = response['total_count'] || items.size

        # Collect field statistics
        field_stats = {}

        items.each do |record|
          record.each do |key, value|
            next if ['id', 'application_id', 'first_created', 'last_updated', 'autonumber'].include?(key)

            field_stats[key] ||= {}

            # Count values for this field
            value_key = value.to_s[0...50] # Truncate long values
            field_stats[key][value_key] ||= 0
            field_stats[key][value_key] += 1
          end
        end

        # Build summary text
        summary_lines = ["Found #{items.size} records (total: #{total})"]

        field_stats.each do |field, values|
          if values.size <= 10
            value_summary = values.map { |v, count| "#{v} (#{count})" }.join(", ")
            summary_lines << "  #{field}: #{value_summary}"
          else
            summary_lines << "  #{field}: #{values.size} unique values"
          end
        end

        result = {
          'summary': summary_lines.join("\n"),
          'count': items.size,
          'total_count': total,
          'fields_analyzed': field_stats.keys
        }

        tokens = estimate_tokens(JSON.generate(result))
        log_metric("✓ Summary: #{items.size} records analyzed")
        log_metric("📊 Minimal context (summary mode)")
        log_token_usage(tokens)

        result
      end

      # Formats records as human-readable plain text.
      #
      # Converts record array to indented text format. Saves ~40% tokens
      # compared to JSON representation.
      #
      # @param records [Array<Hash>] Filtered record data
      # @param total_count [Integer, nil] Total record count for header
      # @param full_content [Boolean] Whether content is already full (no truncation applied)
      # @return [String] Plain text formatted records
      def format_as_plain_text(records, total_count, full_content: false)
        return "No records found." if records.empty?

        lines = []
        lines << "Found #{records.size} records (total: #{total_count || records.size})"
        lines << ""

        records.each_with_index do |record, index|
          lines << "Record #{index + 1}:"
          record.each do |key, value|
            # Format value appropriately - values are already truncated by truncate_value if needed
            # We don't truncate again here (removed the 100-char limit)
            formatted_value = case value
            when Hash
              value.inspect # No truncation - already handled
            when Array
              value.join(", ") # No truncation - already handled
            else
              value.to_s
            end
            lines << "  #{key}: #{formatted_value}"
          end
          lines << ""
        end

        lines.join("\n")
      end

      # Filters a record to only include specified fields.
      #
      # Applies truncation to field values unless full_content is true.
      #
      # @param record [Hash] Complete record data
      # @param include_fields [Array<String>] Field slugs to include
      # @param full_content [Boolean] Skip value truncation (default: false)
      # @return [Hash] Filtered record with only specified fields
      def filter_record_fields(record, include_fields, full_content: false)
        return record unless record.is_a?(Hash)

        # Only include specified fields
        result = {}
        include_fields.each do |field|
          result[field] = truncate_value(record[field], full_content: full_content) if record.key?(field)
        end
        result
      end

      # Truncates field values to prevent excessive token usage.
      #
      # Applies different truncation strategies by value type:
      # - Strings: 500 char limit
      # - Rich text (hashes): Extract preview only
      # - Arrays: First 10 items
      #
      # @param value [Object] Field value to truncate
      # @param full_content [Boolean] Skip truncation if true (default: false)
      # @return [Object] Truncated or original value
      def truncate_value(value, full_content: false)
        # If full_content is true, return value as-is (no truncation)
        return value if full_content

        # Default behavior: truncate to 500 chars for safety
        case value
        when String
          value.length > 500 ? value[0...500] + '... [truncated]' : value
        when Hash
          # For nested hashes (like description), truncate aggressively
          if value['html'] || value['data'] || value['yjsData']
            # This is likely a rich text field - just keep preview
            value['preview'] ? value['preview'][0...500] : '[Rich text content]'
          else
            value
          end
        when Array
          # Truncate arrays to first 10 items
          value.length > 10 ? value[0...10] + ['... [truncated]'] : value
        else
          value
        end
      end
    end
  end
end
