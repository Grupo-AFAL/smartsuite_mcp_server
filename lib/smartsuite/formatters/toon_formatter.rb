# frozen_string_literal: true

require "toon"

module SmartSuite
  module Formatters
    # ToonFormatter provides TOON (Token-Oriented Object Notation) formatting
    # for SmartSuite responses to minimize token usage when passing data to LLMs.
    #
    # TOON typically provides 30-60% token savings over JSON while maintaining
    # readability. It uses indentation-based structure and tabular layouts
    # for uniform arrays of objects.
    #
    # @example Format records as TOON
    #   records = [{'id' => '123', 'title' => 'Task 1'}, {'id' => '456', 'title' => 'Task 2'}]
    #   ToonFormatter.format_records(records, total_count: 100)
    #
    # @see https://github.com/toon-format/toon TOON format specification
    # @see https://github.com/andrepcg/toon-ruby toon-ruby gem
    module ToonFormatter
      extend self

      # Formats a list of records using TOON encoding.
      #
      # @param records [Array<Hash>] Array of record hashes
      # @param total_count [Integer, nil] Total records in table
      # @param filtered_count [Integer, nil] Records matching filter
      # @param options [Hash] TOON encoding options
      # @option options [String] :delimiter Separator character (',' or '|' or "\t")
      # @return [String] TOON-formatted records
      def format_records(records, total_count: nil, filtered_count: nil, **options)
        return format_empty_result(total_count, filtered_count) if records.empty?

        filtered_count ||= total_count
        header = build_header(records.size, total_count, filtered_count)

        data = { "records" => records }
        toon_output = Toon.encode(data, **toon_options(options))

        "#{header}\n#{toon_output}"
      end

      # Formats a single record using TOON encoding.
      #
      # @param record [Hash] Record data
      # @param options [Hash] TOON encoding options
      # @return [String] TOON-formatted record
      def format_record(record, **options)
        Toon.encode(record, **toon_options(options))
      end

      # Formats solutions list using TOON encoding.
      #
      # @param solutions [Array<Hash>] Array of solution hashes
      # @param options [Hash] TOON encoding options
      # @return [String] TOON-formatted solutions
      def format_solutions(solutions, **options)
        return "solutions[0]:" if solutions.empty?

        data = { "solutions" => solutions }
        Toon.encode(data, **toon_options(options))
      end

      # Formats tables list using TOON encoding.
      #
      # @param tables [Array<Hash>] Array of table hashes
      # @param options [Hash] TOON encoding options
      # @return [String] TOON-formatted tables
      def format_tables(tables, **options)
        return "tables[0]:" if tables.empty?

        data = { "tables" => tables }
        Toon.encode(data, **toon_options(options))
      end

      # Formats members list using TOON encoding.
      #
      # @param members [Array<Hash>] Array of member hashes
      # @param options [Hash] TOON encoding options
      # @return [String] TOON-formatted members
      def format_members(members, **options)
        return "members[0]:" if members.empty?

        data = { "members" => members }
        Toon.encode(data, **toon_options(options))
      end

      # Formats any generic data using TOON encoding.
      #
      # @param data [Object] Data to encode (Hash, Array, or primitive)
      # @param options [Hash] TOON encoding options
      # @return [String] TOON-formatted data
      def format(data, **options)
        Toon.encode(data, **toon_options(options))
      end

      private

      # Builds header line showing record counts.
      #
      # @param shown [Integer] Records displayed
      # @param total [Integer, nil] Total in table
      # @param filtered [Integer, nil] Matching filter
      # @return [String] Header line
      def build_header(shown, total, filtered)
        if filtered && filtered < total
          "=== Showing #{shown} of #{filtered} filtered records (#{total} total) ==="
        else
          "=== Showing #{shown} of #{total || shown} total records ==="
        end
      end

      # Formats empty result message.
      #
      # @param total [Integer, nil] Total records
      # @param filtered [Integer, nil] Filtered count
      # @return [String] Empty result message
      def format_empty_result(total, filtered)
        if filtered && filtered < total
          "No records found (0 shown from #{filtered} matching filter, #{total} total)."
        else
          "No records found (0 of #{total || 0} total)."
        end
      end

      # Merges user options with defaults for TOON encoding.
      #
      # @param options [Hash] User-provided options
      # @return [Hash] Merged options
      def toon_options(options)
        {
          indent: 2,
          delimiter: ","
        }.merge(options)
      end
    end
  end
end
