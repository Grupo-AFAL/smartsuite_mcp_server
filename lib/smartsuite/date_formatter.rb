# frozen_string_literal: true

require 'time'

module SmartSuite
  # DateFormatter handles conversion of UTC timestamps to local time.
  #
  # SmartSuite stores all dates in UTC. This module converts them to the
  # user's local timezone for display, making dates more intuitive.
  #
  # ## Timezone Configuration (in order of priority)
  #
  # 1. **Programmatic**: Set `DateFormatter.timezone = 'America/Mexico_City'` or `:utc`
  # 2. **Environment variable**: Set `SMARTSUITE_TIMEZONE=America/New_York` or `+0500`
  # 3. **System TZ variable**: Ruby respects the standard `TZ` environment variable
  # 4. **System default**: Uses the operating system's local timezone
  #
  # ## Supported timezone formats
  #
  # - Named timezones: `"America/Mexico_City"`, `"Europe/London"`, `"Asia/Tokyo"`
  # - UTC offset: `"+0500"`, `"-0300"`, `"+05:30"`
  # - Special values: `:utc`, `:local`, `:system`
  #
  # Named timezones are preferred as they handle DST transitions correctly.
  #
  # @example Convert a UTC timestamp
  #   SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
  #   #=> "2025-01-15 07:30:00 -0300" (in America/Sao_Paulo timezone)
  #
  # @example Configure named timezone (preferred)
  #   SmartSuite::DateFormatter.timezone = 'America/Mexico_City'
  #   SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
  #   #=> "2025-01-15 04:30:00 -0600"
  #
  # @example Configure timezone offset
  #   SmartSuite::DateFormatter.timezone = '-0500'
  #   SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
  #   #=> "2025-01-15 05:30:00 -0500"
  #
  # @example Keep dates in UTC
  #   SmartSuite::DateFormatter.timezone = :utc
  #   SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
  #   #=> "2025-01-15T10:30:00Z" (unchanged)
  #
  # @example Using environment variable
  #   # In shell: export SMARTSUITE_TIMEZONE=America/New_York
  #   SmartSuite::DateFormatter.to_local('2025-01-15T10:30:00Z')
  #   #=> "2025-01-15 05:30:00 -0500"
  module DateFormatter
    # ISO 8601 timestamp patterns commonly returned by SmartSuite API
    # Matches:
    #   - 2025-01-15T10:30:00Z
    #   - 2025-01-15T10:30:00.123Z
    #   - 2025-01-15T10:30:00+00:00
    #   - 2025-01-15 (date only)
    ISO8601_PATTERN = /\A\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?)?\z/

    # UTC offset pattern (e.g., "+0500", "-03:00")
    UTC_OFFSET_PATTERN = /\A[+-]\d{2}:?\d{2}\z/

    # Named timezone pattern (e.g., "America/Mexico_City", "Europe/London")
    NAMED_TIMEZONE_PATTERN = %r{\A[A-Za-z]+/[A-Za-z_]+(/[A-Za-z_]+)?\z}

    class << self
      # Get the configured timezone.
      #
      # @return [String, Symbol, nil] Timezone name, offset, :utc, :local, or nil (system default)
      attr_reader :timezone

      # Set the timezone for date conversion.
      #
      # @param value [String, Symbol, nil] Timezone value:
      #   - Named timezone: "America/Mexico_City", "Europe/London"
      #   - UTC offset string: "+0500", "-03:00"
      #   - :utc - Keep times in UTC (no conversion)
      #   - :local or :system - Use system timezone (default behavior)
      #   - nil - Use environment variable or system timezone
      def timezone=(value)
        @timezone = normalize_timezone(value)
      end

      # Reset timezone configuration to default (system timezone).
      def reset_timezone!
        @timezone = nil
      end

      private

      # Normalize timezone value to a consistent format.
      def normalize_timezone(value)
        case value
        when nil, '', :local, :system
          nil # Use system timezone
        when :utc
          :utc
        when UTC_OFFSET_PATTERN
          value.to_s.delete(':') # Normalize to "+0500" format
        when NAMED_TIMEZONE_PATTERN
          # Named timezone (e.g., "America/Mexico_City") - store as-is
          value.to_s.strip
        when String
          # Other strings - store as-is (may be a named timezone variant)
          value.to_s.strip
        end
      end
    end

    module_function

    # Convert a UTC timestamp to local time.
    #
    # Accepts two formats:
    # 1. Plain timestamp string: "2025-01-15T10:30:00Z"
    # 2. Hash with include_time flag: {date: "2025-01-15T00:00:00Z", include_time: false}
    #
    # When include_time is false, the timestamp represents a calendar day and
    # should NOT be timezone-converted (prevents "Feb 1" becoming "Jan 31").
    #
    # @param value [String, Hash] ISO 8601 timestamp or date hash with include_time flag
    # @return [String] Formatted local time string, or date-only for date fields
    # @example Plain timestamp
    #   DateFormatter.to_local('2025-01-15T10:30:00Z')
    #   #=> "2025-01-15 07:30:00 -0300"
    # @example Date-only (include_time: false)
    #   DateFormatter.to_local({'date' => '2025-02-01T00:00:00Z', 'include_time' => false})
    #   #=> "2025-02-01"
    def to_local(value)
      # Handle hash format with include_time flag
      if value.is_a?(Hash)
        date_str = value['date'] || value[:date]
        include_time = value['include_time'] || value[:include_time]
        return convert_date_with_flag(date_str, include_time)
      end

      # Handle plain string format (legacy behavior)
      return value unless value.is_a?(String)
      return value unless timestamp?(value)

      time = Time.parse(value)
      effective_tz = effective_timezone

      # If UTC mode, return original timestamp unchanged
      return value if effective_tz == :utc

      # If it's a date-only format (no time component), return as-is
      # Date-only values represent calendar days, not instants in time
      return value if date_only?(value)

      convert_time(time, effective_tz).strftime('%Y-%m-%d %H:%M:%S %z')
    rescue ArgumentError
      # Return original if parsing fails
      value
    end

    # Convert a date string using the include_time flag.
    #
    # Uses smart detection to work around SmartSuite API bugs where include_time
    # is incorrectly set to false for duedatefield/daterangefield types.
    #
    # Logic:
    # - If time is NOT midnight UTC → treat as datetime (has time, convert timezone)
    # - If time IS midnight UTC → only treat as datetime if include_time is true
    #
    # @param date_str [String] ISO 8601 timestamp
    # @param include_time [Boolean] Whether the date includes a time component
    # @return [String] Formatted date/datetime string
    def convert_date_with_flag(date_str, include_time)
      return date_str unless date_str.is_a?(String)
      return date_str unless timestamp?(date_str)

      time = Time.parse(date_str)
      effective_tz = effective_timezone

      # If UTC mode, return original unchanged
      return date_str if effective_tz == :utc

      # Smart detection: non-midnight UTC always means datetime
      # Midnight UTC is date-only unless include_time explicitly says otherwise
      has_time = if midnight_utc?(time)
                   include_time # Trust include_time flag for midnight
                 else
                   true # Non-midnight always has time component
                 end

      if has_time
        # Has time component - convert to local timezone
        convert_time(time, effective_tz).strftime('%Y-%m-%d %H:%M:%S %z')
      else
        # Date-only - return just the date from the UTC timestamp (no conversion)
        time.utc.strftime('%Y-%m-%d')
      end
    rescue ArgumentError
      date_str
    end

    # Check if a time is midnight UTC (00:00:00).
    #
    # @param time [Time] Time object to check
    # @return [Boolean] true if time is midnight UTC
    def midnight_utc?(time)
      utc_time = time.utc
      utc_time.hour.zero? && utc_time.min.zero? && utc_time.sec.zero?
    end

    # Get the effective timezone considering all configuration sources.
    #
    # Priority: programmatic config > SMARTSUITE_TIMEZONE env > system
    #
    # @return [String, Symbol, nil] Effective timezone setting
    def effective_timezone
      # Check programmatic configuration first
      return DateFormatter.timezone if DateFormatter.timezone

      # Check environment variable
      env_tz = ENV.fetch('SMARTSUITE_TIMEZONE', nil)
      return nil if env_tz.nil? || env_tz.empty?

      # Normalize environment variable value
      case env_tz.downcase
      when 'utc'
        :utc
      when 'local', 'system'
        nil
      else
        env_tz
      end
    end

    # Convert time to the target timezone.
    #
    # Supports three timezone formats:
    # 1. nil - Use system local timezone
    # 2. UTC offset (e.g., "+0500") - Use explicit offset
    # 3. Named timezone (e.g., "America/Mexico_City") - Use TZ env var temporarily
    #
    # @param time [Time] Time object to convert
    # @param timezone [String, nil] Target timezone (nil = local)
    # @return [Time] Converted time
    def convert_time(time, timezone)
      if timezone.nil?
        # Use system local timezone
        time.localtime
      elsif timezone.match?(UTC_OFFSET_PATTERN)
        # Use explicit UTC offset
        time.getlocal(timezone)
      elsif named_timezone?(timezone)
        # Named timezone - temporarily set TZ env var for conversion
        convert_with_named_timezone(time, timezone)
      else
        # Unknown format, fallback to local
        time.localtime
      end
    end

    # Check if a timezone string is a named timezone (e.g., "America/Mexico_City").
    #
    # @param timezone [String] Timezone string
    # @return [Boolean] true if it looks like a named timezone
    def named_timezone?(timezone)
      return false unless timezone.is_a?(String)

      timezone.match?(NAMED_TIMEZONE_PATTERN)
    end

    # Convert time using a named timezone via TZ environment variable.
    #
    # This temporarily sets TZ, creates a new Time object in that timezone,
    # then restores the original TZ. This approach works with Ruby's stdlib
    # without requiring additional gems like TZInfo.
    #
    # @param time [Time] UTC time to convert
    # @param tz_name [String] Named timezone (e.g., "America/Mexico_City")
    # @return [Time] Time in the target timezone
    def convert_with_named_timezone(time, tz_name)
      original_tz = ENV.fetch('TZ', nil)
      begin
        ENV['TZ'] = tz_name
        # Force Ruby to re-read TZ
        Time.at(time.to_i).localtime
      ensure
        # Restore original TZ (or unset if it wasn't set)
        if original_tz
          ENV['TZ'] = original_tz
        else
          ENV.delete('TZ')
        end
      end
    end

    # Check if a string looks like an ISO 8601 timestamp.
    #
    # @param str [String] String to check
    # @return [Boolean] true if the string matches ISO 8601 pattern
    def timestamp?(str)
      return false unless str.is_a?(String)

      ISO8601_PATTERN.match?(str)
    end

    # Check if timestamp is date-only (no time component).
    #
    # @param str [String] Timestamp string
    # @return [Boolean] true if date-only format
    def date_only?(str)
      str.is_a?(String) && str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    # Recursively convert all timestamp values in a data structure.
    #
    # Walks through hashes and arrays, converting any ISO 8601 timestamps
    # to local time. Useful for processing entire API responses.
    #
    # Recognizes date hashes with include_time flag:
    #   {date: "2025-01-15T00:00:00Z", include_time: false}
    #
    # @param data [Object] Data structure (Hash, Array, or scalar)
    # @return [Object] Data with timestamps converted to local time
    # @example
    #   data = { 'created' => '2025-01-15T10:30:00Z', 'name' => 'Test' }
    #   DateFormatter.convert_all(data)
    #   #=> { 'created' => '2025-01-15 07:30:00 -0300', 'name' => 'Test' }
    def convert_all(data)
      case data
      when Hash
        # Check if this is a date hash with include_time flag
        if date_hash?(data)
          to_local(data)
        else
          data.transform_values { |v| convert_all(v) }
        end
      when Array
        data.map { |v| convert_all(v) }
      when String
        to_local(data)
      else
        data
      end
    end

    # Check if a hash is a date object with include_time flag.
    #
    # @param hash [Hash] Hash to check
    # @return [Boolean] true if it's a date hash
    def date_hash?(hash)
      return false unless hash.is_a?(Hash)

      (hash.key?('date') || hash.key?(:date)) &&
        (hash.key?('include_time') || hash.key?(:include_time))
    end

    # Get current timezone information for display.
    #
    # @return [Hash] Timezone configuration details
    def timezone_info
      eff_tz = effective_timezone
      {
        'configured' => DateFormatter.timezone,
        'environment' => ENV.fetch('SMARTSUITE_TIMEZONE', nil),
        'effective' => eff_tz || 'system',
        'current_offset' => Time.now.strftime('%z'),
        'current_zone' => Time.now.zone,
        'type' => timezone_type(eff_tz)
      }
    end

    # Determine the type of timezone configuration.
    #
    # @param eff_tz [String, Symbol, nil] Effective timezone value
    # @return [String] Timezone type identifier
    def timezone_type(eff_tz)
      if eff_tz == :utc
        'utc'
      elsif eff_tz.nil?
        'system'
      elsif eff_tz.match?(UTC_OFFSET_PATTERN)
        'offset'
      elsif named_timezone?(eff_tz)
        'named'
      else
        'unknown'
      end
    end
  end
end
