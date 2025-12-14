# frozen_string_literal: true

require "date"

module SmartSuite
  # Resolves SmartSuite date_mode values to actual date strings.
  #
  # SmartSuite filters use dynamic date modes like "today", "yesterday", etc.
  # This module converts those to actual date strings (YYYY-MM-DD format).
  #
  # @example Resolve a date mode
  #   DateModeResolver.resolve("today")       # => "2025-12-13"
  #   DateModeResolver.resolve("yesterday")   # => "2025-12-12"
  #
  # @example Extract date from a filter value hash
  #   DateModeResolver.extract_date_value({ "date_mode" => "today" })
  #   # => "2025-12-13"
  #
  #   DateModeResolver.extract_date_value({ "date_mode_value" => "2025-01-15" })
  #   # => "2025-01-15"
  #
  module DateModeResolver
    # Supported date modes and their meanings
    SUPPORTED_MODES = %w[
      today yesterday tomorrow
      one_week_ago one_week_from_now
      one_month_ago one_month_from_now
      start_of_week end_of_week
      start_of_month end_of_month
    ].freeze

    class << self
      # Resolves a date_mode string to an actual date string.
      #
      # @param date_mode [String, nil] The date mode to resolve
      # @return [String, nil] Date string in YYYY-MM-DD format, or nil if date_mode is nil
      #
      # @example
      #   resolve("today")     # => "2025-12-13"
      #   resolve("yesterday") # => "2025-12-12"
      #   resolve(nil)         # => nil
      #   resolve("unknown")   # => "unknown" (returned as-is)
      #
      def resolve(date_mode)
        return nil unless date_mode

        today = Date.today
        case date_mode.to_s.downcase
        when "today"
          today.to_s
        when "yesterday"
          (today - 1).to_s
        when "tomorrow"
          (today + 1).to_s
        when "one_week_ago"
          (today - 7).to_s
        when "one_week_from_now"
          (today + 7).to_s
        when "one_month_ago"
          (today << 1).to_s
        when "one_month_from_now"
          (today >> 1).to_s
        when "start_of_week"
          (today - today.wday).to_s
        when "end_of_week"
          (today + (6 - today.wday)).to_s
        when "start_of_month"
          Date.new(today.year, today.month, 1).to_s
        when "end_of_month"
          Date.new(today.year, today.month, -1).to_s
        else
          # Return unknown modes as-is (might be a date string already)
          date_mode.to_s
        end
      end

      # Extracts a date value from a SmartSuite filter value.
      #
      # SmartSuite date filters can have different formats:
      # - { "date_mode_value" => "2025-01-15" } - explicit date
      # - { "date" => "2025-01-15" } - explicit date (alternative key)
      # - { "date_mode" => "today" } - dynamic date mode
      # - "2025-01-15" - plain string
      #
      # @param value [Hash, String] The filter value
      # @return [String, nil] Date string in YYYY-MM-DD format
      #
      # @example With explicit date
      #   extract_date_value({ "date_mode_value" => "2025-01-15" })
      #   # => "2025-01-15"
      #
      # @example With dynamic date mode
      #   extract_date_value({ "date_mode" => "today" })
      #   # => "2025-12-13"
      #
      # @example With plain string
      #   extract_date_value("2025-03-10")
      #   # => "2025-03-10"
      #
      def extract_date_value(value)
        if value.is_a?(Hash)
          # Priority: date_mode_value > date > date_mode
          return value["date_mode_value"] if value["date_mode_value"]
          return value["date"] if value["date"]

          resolve(value["date_mode"])
        else
          value.to_s
        end
      end

      # Checks if a date_mode is a known dynamic mode.
      #
      # @param date_mode [String] The date mode to check
      # @return [Boolean] true if it's a known dynamic mode
      #
      def dynamic_mode?(date_mode)
        SUPPORTED_MODES.include?(date_mode.to_s.downcase)
      end
    end
  end
end
