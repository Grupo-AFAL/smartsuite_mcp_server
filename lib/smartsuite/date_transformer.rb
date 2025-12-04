# frozen_string_literal: true

require "time"

module SmartSuite
  # DateTransformer provides transparent date handling for AI interactions.
  #
  # This module automatically converts simple date strings to SmartSuite's
  # expected format with `include_time` inferred from the input format.
  #
  # ## Supported Input Formats
  #
  # **Date-only** (include_time: false):
  # - "2025-06-20"
  # - "2025/06/20"
  #
  # **Datetime** (include_time: true):
  # - "2025-06-20T14:30:00Z"
  # - "2025-06-20T14:30:00"
  # - "2025-06-20 14:30"
  # - "2025-06-20 14:30:00"
  #
  # ## Usage
  #
  # The AI can simply provide date strings and the server handles the rest:
  #
  # @example Date-only
  #   {"due_date": {"from_date": "2025-06-20", "to_date": "2025-06-25"}}
  #   # Transformed to:
  #   {"due_date": {"from_date": {"date": "2025-06-20T00:00:00Z", "include_time": false},
  #                "to_date": {"date": "2025-06-25T00:00:00Z", "include_time": false}}}
  #
  # @example With time
  #   {"due_date": {"from_date": "2025-06-20T14:30:00Z", "to_date": "2025-06-25 17:00"}}
  #   # Transformed to:
  #   {"due_date": {"from_date": {"date": "2025-06-20T14:30:00Z", "include_time": true},
  #                "to_date": {"date": "2025-06-25T17:00:00Z", "include_time": true}}}
  #
  module DateTransformer
    # Date-only pattern: YYYY-MM-DD (no time component)
    DATE_ONLY_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

    # Date with slashes: YYYY/MM/DD
    DATE_SLASH_PATTERN = %r{\A\d{4}/\d{2}/\d{2}\z}

    # ISO 8601 datetime: 2025-06-20T14:30:00Z or 2025-06-20T14:30:00
    ISO_DATETIME_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:?\d{2})?\z/

    # Space-separated datetime: 2025-06-20 14:30 or 2025-06-20 14:30:00
    SPACE_DATETIME_PATTERN = /\A\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(:\d{2})?\z/

    # Date field types that need transformation
    DATE_FIELD_TYPES = %w[datefield duedatefield daterangefield].freeze

    # Fields within date structures that contain date values
    DATE_SUBFIELDS = %w[from_date to_date date].freeze

    module_function

    # Transform record data to convert simple date strings to SmartSuite format.
    #
    # Recursively processes the data hash, detecting date fields and converting
    # simple date strings to the {date: ..., include_time: ...} format.
    #
    # @param data [Hash] Record data with potential date fields
    # @param table_structure [Array<Hash>, nil] Optional table structure for field type hints
    # @return [Hash] Transformed data with properly formatted dates
    def transform_dates(data, table_structure = nil)
      return data unless data.is_a?(Hash)

      field_types = build_field_type_map(table_structure) if table_structure

      data.transform_values.with_index do |(key, value), _idx|
        key_str = key.to_s
        transform_field_value(key_str, value, field_types)
      end.to_h.transform_keys(&:to_s)

      # Re-transform using keys properly
      result = {}
      data.each do |key, value|
        key_str = key.to_s
        result[key_str] = transform_field_value(key_str, value, field_types)
      end
      result
    end

    # Transform a single field value based on its structure.
    #
    # @param field_name [String] Field slug/name
    # @param value [Object] Field value
    # @param field_types [Hash, nil] Map of field names to their types
    # @return [Object] Transformed value
    def transform_field_value(field_name, value, field_types = nil)
      return value if value.nil?

      # Check if this looks like a date field by name or type
      is_date_field = date_field?(field_name, field_types)

      case value
      when String
        # Simple string - could be a date value
        if is_date_field || looks_like_date?(value)
          transform_date_string(value)
        else
          value
        end
      when Hash
        # Could be a date range structure or nested data
        if date_structure?(value)
          transform_date_hash(value)
        else
          # Recursively transform nested hashes
          transform_dates(value, nil)
        end
      else
        value
      end
    end

    # Check if a field is a date field based on name or type map.
    #
    # @param field_name [String] Field name/slug
    # @param field_types [Hash, nil] Map of field names to types
    # @return [Boolean]
    def date_field?(field_name, field_types = nil)
      return true if field_types&.dig(field_name)&.match?(/date/i)

      # Heuristic: common date field names
      field_name.match?(/date|fecha|due|created|updated|vencimiento/i)
    end

    # Check if a string looks like a date value.
    #
    # @param str [String] String to check
    # @return [Boolean]
    def looks_like_date?(str)
      return false unless str.is_a?(String)

      DATE_ONLY_PATTERN.match?(str) ||
        DATE_SLASH_PATTERN.match?(str) ||
        ISO_DATETIME_PATTERN.match?(str) ||
        SPACE_DATETIME_PATTERN.match?(str)
    end

    # Check if a hash looks like a date structure (has from_date, to_date, or date keys).
    #
    # @param hash [Hash] Hash to check
    # @return [Boolean]
    def date_structure?(hash)
      return false unless hash.is_a?(Hash)

      keys = hash.keys.map(&:to_s)
      (keys & DATE_SUBFIELDS).any? || keys.include?("include_time")
    end

    # Transform a simple date string to SmartSuite format.
    #
    # @param str [String] Date string
    # @return [Hash, String] Transformed date hash or original string if not a date
    def transform_date_string(str)
      return str unless str.is_a?(String)

      if date_only?(str)
        # Date-only: normalize to ISO format at midnight UTC
        date = parse_date_only(str)
        return str unless date

        {
          "date" => "#{date}T00:00:00Z",
          "include_time" => false
        }
      elsif datetime?(str)
        # Has time component
        normalized = normalize_datetime(str)
        return str unless normalized

        {
          "date" => normalized,
          "include_time" => true
        }
      else
        str
      end
    end

    # Transform a hash that contains date values.
    #
    # Handles structures like:
    # - {from_date: "2025-06-20", to_date: "2025-06-25"}
    # - {date: "2025-06-20T14:30:00Z"}
    # - Already formatted: {date: "...", include_time: true}
    #
    # @param hash [Hash] Date hash structure
    # @return [Hash] Transformed hash
    def transform_date_hash(hash)
      result = {}

      hash.each do |key, value|
        key_str = key.to_s

        if DATE_SUBFIELDS.include?(key_str)
          result[key_str] = if value.is_a?(String)
                              transform_date_string(value)
          elsif value.is_a?(Hash) && value.key?("date")
                              # Already in correct format, ensure include_time is set
                              ensure_include_time(value)
          else
                              value
          end
        elsif key_str == "include_time"
          # Skip - will be set by transform_date_string
          next
        else
          # Pass through other keys (is_overdue, status_is_completed, etc.)
          result[key_str] = value
        end
      end

      result
    end

    # Ensure a date hash has include_time set correctly.
    #
    # @param hash [Hash] Date hash with 'date' key
    # @return [Hash] Hash with include_time set
    def ensure_include_time(hash)
      return hash unless hash.is_a?(Hash) && hash["date"]

      # If include_time is already set, trust it
      return hash if hash.key?("include_time")

      # Infer from the date string
      date_str = hash["date"].to_s
      has_time = datetime?(date_str) && !midnight_utc?(date_str)

      hash.merge("include_time" => has_time)
    end

    # Check if a string is date-only (no time component).
    #
    # @param str [String] String to check
    # @return [Boolean]
    def date_only?(str)
      DATE_ONLY_PATTERN.match?(str) || DATE_SLASH_PATTERN.match?(str)
    end

    # Check if a string has a time component.
    #
    # @param str [String] String to check
    # @return [Boolean]
    def datetime?(str)
      ISO_DATETIME_PATTERN.match?(str) || SPACE_DATETIME_PATTERN.match?(str)
    end

    # Check if a datetime string represents midnight UTC.
    #
    # @param str [String] ISO datetime string
    # @return [Boolean]
    def midnight_utc?(str)
      return false unless str.is_a?(String)

      str.match?(/T00:00:00(\.0+)?Z?\z/)
    end

    # Parse a date-only string to YYYY-MM-DD format.
    #
    # @param str [String] Date string
    # @return [String, nil] Normalized date or nil if parsing fails
    def parse_date_only(str)
      if DATE_SLASH_PATTERN.match?(str)
        str.tr("/", "-")
      else
        str
      end
    rescue StandardError
      nil
    end

    # Normalize a datetime string to ISO 8601 UTC format.
    #
    # Converts any timezone to UTC with Z suffix. SmartSuite API expects UTC.
    #
    # @param str [String] Datetime string (may include timezone offset)
    # @return [String, nil] Normalized UTC datetime or nil if parsing fails
    # @example
    #   normalize_datetime("2025-06-20T14:30:00Z")       #=> "2025-06-20T14:30:00Z"
    #   normalize_datetime("2025-06-20T14:30:00-07:00") #=> "2025-06-20T21:30:00Z"
    #   normalize_datetime("2025-06-20T14:30:00+05:30") #=> "2025-06-20T09:00:00Z"
    #   normalize_datetime("2025-06-20 14:30")          #=> "2025-06-20T14:30:00Z"
    def normalize_datetime(str)
      if ISO_DATETIME_PATTERN.match?(str)
        # ISO format - may have timezone offset, convert to UTC
        if str.end_with?("Z")
          str
        elsif str.match?(/[+-]\d{2}:?\d{2}\z/)
          # Has timezone offset - parse and convert to UTC
          convert_to_utc(str)
        else
          # No timezone - assume UTC
          "#{str}Z"
        end
      elsif SPACE_DATETIME_PATTERN.match?(str)
        # Space-separated: "2025-06-20 14:30" or "2025-06-20 14:30:00"
        # Assume UTC (no timezone specified)
        parts = str.split(/\s+/)
        date = parts[0]
        time = parts[1]
        time = "#{time}:00" unless time.match?(/:\d{2}:\d{2}/)
        "#{date}T#{time}Z"
      end
    rescue StandardError
      nil
    end

    # Convert a datetime with timezone offset to UTC.
    #
    # @param str [String] ISO datetime with timezone offset (e.g., "2025-06-20T14:30:00-07:00")
    # @return [String] UTC datetime with Z suffix
    def convert_to_utc(str)
      time = Time.parse(str)
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    rescue StandardError
      # If parsing fails, return with Z suffix as fallback
      str.sub(/[+-]\d{2}:?\d{2}\z/, "Z")
    end

    # Build a map of field names to their types from table structure.
    #
    # @param structure [Array<Hash>] Table structure array
    # @return [Hash] Map of field slug to field type
    def build_field_type_map(structure)
      return {} unless structure.is_a?(Array)

      structure.each_with_object({}) do |field, map|
        slug = field["slug"] || field[:slug]
        type = field["field_type"] || field[:field_type]
        map[slug] = type if slug && type
      end
    end
  end
end
