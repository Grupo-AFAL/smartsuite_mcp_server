# frozen_string_literal: true

require "digest"
require "time"
require "sqlite3"
require_relative "smart_suite/paths"
require_relative "smart_suite/cache/schema"

# ApiStatsTracker tracks API usage statistics in SQLite database
#
# Stores aggregated statistics and individual API call records for analysis.
# Now uses the same SQLite database as the cache layer for consolidated storage.
class ApiStatsTracker
  def initialize(api_key, db: nil, session_id: nil)
    @api_key = api_key
    @user_hash = Digest::SHA256.hexdigest(api_key)[0..7]
    @session_id = session_id || generate_session_id

    # Use provided database connection or create new one
    @db = db
    @owns_db = db.nil?

    return unless @owns_db

    # Create our own database if none provided
    # Uses SmartSuite::Paths for consistent path handling (test mode vs production)
    @db = SQLite3::Database.new(SmartSuite::Paths.database_path)
    @db.results_as_hash = true

    # Create tables if we own the database (they may not exist if CacheLayer wasn't used)
    setup_tables
  end

  private

  # Create required tables if they don't exist
  # These are normally created by CacheLayer.setup_metadata_tables, but we need them
  # if ApiStatsTracker is used standalone without CacheLayer
  def setup_tables
    # Use centralized schema definitions for API stats tables
    @db.execute_batch(SmartSuite::Cache::Schema.api_stats_tables_sql)
  end

  public

  # Generate a unique session identifier
  #
  # Creates a session ID combining timestamp and random string for tracking
  # API calls within a single session.
  #
  # @return [String] session ID in format "YYYYMMDD_HHMMSS_random"
  # @example
  #   generate_session_id #=> "20250116_143022_8x4k2p"
  def generate_session_id
    # Generate a unique session ID: timestamp + random string
    "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{rand(36**6).to_s(36)}"
  end

  # Track an API call to SmartSuite
  #
  # Records individual API call details and updates aggregated statistics.
  # Automatically extracts solution and table IDs from the endpoint URL.
  #
  # @param method [Symbol, String] HTTP method (GET, POST, PUT, DELETE)
  # @param endpoint [String] API endpoint URL
  # @return [void]
  # @note Failures are silently logged to avoid interrupting user operations
  # @example
  #   track_api_call(:get, '/api/v1/solutions/')
  #   track_api_call(:post, '/api/v1/applications/tbl_123/records/list/')
  def track_api_call(method, endpoint)
    method_name = method.to_s.upcase
    timestamp = Time.now.utc.iso8601

    # Extract IDs from endpoint
    solution_id = extract_solution_id(endpoint)
    table_id = extract_table_id(endpoint)

    # Insert individual call record with session tracking
    @db.execute(
      "INSERT INTO api_call_log (user_hash, session_id, method, endpoint, solution_id, table_id, timestamp)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      [ @user_hash, @session_id, method_name, endpoint, solution_id, table_id, timestamp ]
    )

    # Update aggregated stats
    update_aggregated_stats(method_name, endpoint, solution_id, table_id)
  rescue StandardError => e
    # Silently fail - stats tracking should never interrupt user work
    warn "Stats tracking failed: #{e.message}" if ENV["DEBUG"]
  end

  # Get API usage statistics
  #
  # Returns comprehensive statistics including total calls, breakdowns by method,
  # solution, table, endpoint, and cache performance metrics.
  #
  # @param time_range [String] time filter: 'session' (current session), '7d' (last 7 days), 'all' (all time)
  # @return [Hash] statistics hash with summary and breakdowns
  # @example
  #   stats = get_stats(time_range: 'session')
  #   puts stats['summary']['total_calls'] #=> 42
  #   puts stats['cache_stats']['hit_rate'] #=> 85.5
  def get_stats(time_range: "all")
    # Validate time_range parameter
    valid_ranges = %w[session 7d all]
    time_range = "all" unless valid_ranges.include?(time_range)

    # Build time filter SQL
    time_filter = build_time_filter(time_range)

    summary = @db.execute("SELECT * FROM api_stats_summary WHERE user_hash = ?", [ @user_hash ]).first

    unless summary
      return {
        "time_range" => time_range,
        "summary" => {
          "total_calls" => 0,
          "first_call" => nil,
          "last_call" => nil,
          "unique_users" => 0,
          "unique_solutions" => 0,
          "unique_tables" => 0
        },
        "by_method" => {},
        "by_solution" => {},
        "by_table" => {},
        "by_endpoint" => {},
        "cache_stats" => get_cache_stats(time_filter)
      }
    end

    {
      "time_range" => time_range,
      "summary" => {
        "total_calls" => get_call_count_filtered(time_filter),
        "first_call" => summary["first_call"],
        "last_call" => summary["last_call"],
        "unique_users" => get_unique_count("user_hash", time_filter),
        "unique_solutions" => get_unique_count("solution_id", time_filter),
        "unique_tables" => get_unique_count("table_id", time_filter)
      },
      "by_method" => get_breakdown_by("method", time_filter),
      "by_solution" => get_breakdown_by("solution_id", time_filter),
      "by_table" => get_breakdown_by("table_id", time_filter),
      "by_endpoint" => get_breakdown_by("endpoint", time_filter),
      "cache_stats" => get_cache_stats(time_filter)
    }
  end

  # Reset all API statistics for the current user
  #
  # Deletes all API call logs and aggregated statistics for this user.
  # Useful for clearing historical data or starting fresh tracking.
  #
  # @return [Hash] status hash with 'status' and 'message' keys
  # @example Success response
  #   reset_stats #=> {"status" => "success", "message" => "API statistics have been reset"}
  # @example Error response
  #   reset_stats #=> {"status" => "error", "message" => "Failed to reset stats: ..."}
  def reset_stats
    @db.execute("DELETE FROM api_call_log WHERE user_hash = ?", [ @user_hash ])
    @db.execute("DELETE FROM api_stats_summary WHERE user_hash = ?", [ @user_hash ])

    {
      "status" => "success",
      "message" => "API statistics have been reset"
    }
  rescue StandardError => e
    {
      "status" => "error",
      "message" => "Failed to reset stats: #{e.message}"
    }
  end

  # Close the database connection
  #
  # Safely closes the SQLite database connection if this instance owns it.
  # Only closes connections created by this tracker, not shared connections.
  #
  # @return [void]
  # @note Call this when shutting down to ensure proper resource cleanup
  # @example
  #   tracker.close  # Closes database if owned by this instance
  def close
    @db.close if @owns_db && @db
  end

  private

  def update_aggregated_stats(_method_name, _endpoint, _solution_id, _table_id)
    timestamp = Time.now.utc.iso8601

    # Upsert summary stats
    @db.execute(
      "INSERT INTO api_stats_summary (user_hash, total_calls, first_call, last_call)
       VALUES (?, 1, ?, ?)
       ON CONFLICT(user_hash) DO UPDATE SET
         total_calls = total_calls + 1,
         first_call = COALESCE(first_call, excluded.first_call),
         last_call = excluded.last_call",
      [ @user_hash, timestamp, timestamp ]
    )
  end

  def build_time_filter(time_range)
    case time_range
    when "session"
      "AND session_id = '#{@session_id}'"
    when "7d"
      seven_days_ago = (Time.now.utc - (7 * 24 * 60 * 60)).iso8601
      "AND timestamp >= '#{seven_days_ago}'"
    else # 'all'
      ""
    end
  end

  def get_call_count_filtered(time_filter)
    result = @db.execute(
      "SELECT COUNT(*) as count
       FROM api_call_log
       WHERE user_hash = ? #{time_filter}",
      [ @user_hash ]
    ).first

    result ? result["count"] : 0
  end

  def get_unique_count(column, time_filter = "")
    return 0 if column.nil?

    result = @db.execute(
      "SELECT COUNT(DISTINCT #{column}) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL #{time_filter}",
      [ @user_hash ]
    ).first

    result ? result["count"] : 0
  end

  def get_breakdown_by(column, time_filter = "")
    results = @db.execute(
      "SELECT #{column}, COUNT(*) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL #{time_filter}
       GROUP BY #{column}
       ORDER BY count DESC",
      [ @user_hash ]
    )

    results.each_with_object({}) do |row, hash|
      hash[row[column]] = row["count"]
    end
  end

  def get_cache_stats(time_filter)
    # Query cache_performance table for all tables
    perf_results = @db.execute(
      "SELECT * FROM cache_performance ORDER BY table_id"
    )

    return empty_cache_stats if perf_results.empty?

    # Calculate overall cache metrics
    total_hits = perf_results.sum { |r| r["hit_count"] || 0 }
    total_misses = perf_results.sum { |r| r["miss_count"] || 0 }
    total_operations = total_hits + total_misses

    # Calculate efficiency: cache hits saved API calls
    # Each cache hit = 1+ API calls saved (pagination means 1 miss can = multiple API calls)
    api_calls_made = get_call_count_filtered(time_filter)

    # Estimate API calls that would have been made without cache
    # Conservative estimate: each cache hit saved 1 API call
    api_calls_saved = total_hits
    api_calls_without_cache = api_calls_made + api_calls_saved

    # Calculate hit rate and efficiency ratio
    hit_rate = total_operations.positive? ? (total_hits.to_f / total_operations * 100).round(2) : 0.0
    efficiency_ratio = api_calls_without_cache.positive? ? (api_calls_saved.to_f / api_calls_without_cache * 100).round(2) : 0.0

    # Estimate token savings
    # Conservative: each cache hit saves ~500 tokens (vs API call + response parsing)
    estimated_tokens_saved = total_hits * 500

    # Build per-table breakdown
    by_table = perf_results.map do |row|
      table_total = (row["hit_count"] || 0) + (row["miss_count"] || 0)
      table_hit_rate = table_total.positive? ? ((row["hit_count"] || 0).to_f / table_total * 100).round(2) : 0.0

      {
        "table_id" => row["table_id"],
        "hit_count" => row["hit_count"] || 0,
        "miss_count" => row["miss_count"] || 0,
        "total_operations" => table_total,
        "hit_rate" => table_hit_rate,
        "record_count" => row["record_count"] || 0,
        "cache_size_bytes" => row["cache_size_bytes"] || 0,
        "last_access" => row["last_access_time"]
      }
    end

    {
      "summary" => {
        "total_cache_hits" => total_hits,
        "total_cache_misses" => total_misses,
        "total_cache_operations" => total_operations,
        "overall_hit_rate" => hit_rate,
        "api_calls_made" => api_calls_made,
        "api_calls_saved" => api_calls_saved,
        "api_calls_without_cache" => api_calls_without_cache,
        "efficiency_ratio" => efficiency_ratio,
        "estimated_tokens_saved" => estimated_tokens_saved
      },
      "by_table" => by_table
    }
  end

  def empty_cache_stats
    {
      "summary" => {
        "total_cache_hits" => 0,
        "total_cache_misses" => 0,
        "total_cache_operations" => 0,
        "overall_hit_rate" => 0.0,
        "api_calls_made" => 0,
        "api_calls_saved" => 0,
        "api_calls_without_cache" => 0,
        "efficiency_ratio" => 0.0,
        "estimated_tokens_saved" => 0
      },
      "by_table" => []
    }
  end

  def extract_solution_id(endpoint)
    endpoint =~ %r{/solutions/([^/?]+)} ? ::Regexp.last_match(1) : nil
  end

  def extract_table_id(endpoint)
    endpoint =~ %r{/applications/([^/?]+)} ? ::Regexp.last_match(1) : nil
  end
end
