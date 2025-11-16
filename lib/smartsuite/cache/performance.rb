# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'time'

module SmartSuite
  module Cache
    # Performance handles hit/miss tracking and performance statistics.
    #
    # This module is responsible for:
    # - Tracking cache hits and misses for performance monitoring
    # - Maintaining in-memory counters with periodic flush to database
    # - Providing cache performance statistics and metrics
    # - Calculating hit rates and efficiency metrics
    #
    # @note Performance tracking uses batch writes to minimize database overhead
    module Performance
      # Track cache hit for performance monitoring
      #
      # @param table_id [String] SmartSuite table ID
      # @return [void]
      def track_cache_hit(table_id)
        @perf_counters[table_id][:hits] += 1
        @perf_operations_since_flush += 1
        flush_performance_counters_if_needed
      end

      # Track cache miss for performance monitoring
      #
      # @param table_id [String] SmartSuite table ID
      # @return [void]
      def track_cache_miss(table_id)
        @perf_counters[table_id][:misses] += 1
        @perf_operations_since_flush += 1
        flush_performance_counters_if_needed
      end

      # Flush performance counters to database if threshold reached
      #
      # Flushes when either:
      # - 100 operations have occurred since last flush
      # - 5 minutes have passed since last flush
      #
      # @return [void]
      def flush_performance_counters_if_needed
        should_flush = @perf_operations_since_flush >= 100 ||
                       (Time.now.utc - @perf_last_flush) >= 300 # 5 minutes

        flush_performance_counters if should_flush
      end

      # Flush all in-memory performance counters to database
      #
      # Batch updates all performance counters to the cache_performance table.
      # Merges in-memory counters with existing database values.
      #
      # @return [void]
      def flush_performance_counters
        return if @perf_counters.empty?

        now = Time.now.utc.iso8601

        @perf_counters.each do |table_id, counters|
          # Get current values from database
          current = db_execute(
            'SELECT hit_count, miss_count FROM cache_performance WHERE table_id = ?',
            table_id
          ).first

          if current
            # Update existing record
            new_hits = current['hit_count'] + counters[:hits]
            new_misses = current['miss_count'] + counters[:misses]

            db_execute(
              "UPDATE cache_performance
             SET hit_count = ?, miss_count = ?, last_access_time = ?, updated_at = ?
             WHERE table_id = ?",
              new_hits, new_misses, now, now, table_id
            )
          else
            # Insert new record
            db_execute(
              "INSERT INTO cache_performance
             (table_id, hit_count, miss_count, last_access_time, updated_at)
             VALUES (?, ?, ?, ?, ?)",
              table_id, counters[:hits], counters[:misses], now, now
            )
          end
        end

        # Reset counters
        @perf_counters.clear
        @perf_operations_since_flush = 0
        @perf_last_flush = Time.now.utc
      end

      # Get cache performance statistics
      #
      # Returns performance metrics for each table including hit/miss counts,
      # hit rates, and cache size information.
      #
      # @param table_id [String, nil] Optional table ID to filter by
      # @return [Array<Hash>] Performance statistics
      def get_cache_performance(table_id: nil)
        # Flush current counters first
        flush_performance_counters

        results = if table_id
                    db_execute(
                      'SELECT * FROM cache_performance WHERE table_id = ?',
                      table_id
                    )
                  else
                    db_execute('SELECT * FROM cache_performance ORDER BY last_access_time DESC')
                  end

        results.map do |row|
          total = row['hit_count'] + row['miss_count']
          {
            'table_id' => row['table_id'],
            'hit_count' => row['hit_count'],
            'miss_count' => row['miss_count'],
            'total_operations' => total,
            'hit_rate' => total.positive? ? (row['hit_count'].to_f / total * 100).round(2) : 0.0,
            'last_access_time' => row['last_access_time'],
            'record_count' => row['record_count'],
            'cache_size_bytes' => row['cache_size_bytes']
          }
        end
      end
    end
  end
end
