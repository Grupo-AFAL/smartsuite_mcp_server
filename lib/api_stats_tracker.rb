require 'digest'
require 'time'
require 'sqlite3'

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

    if @owns_db
      # Create our own database if none provided
      db_path = File.join(Dir.home, '.smartsuite_mcp_cache.db')
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      # Tables will be created by CacheLayer setup_metadata_tables
    end
  end

  def generate_session_id
    # Generate a unique session ID: timestamp + random string
    "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{rand(36**6).to_s(36)}"
  end

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
      [@user_hash, @session_id, method_name, endpoint, solution_id, table_id, timestamp]
    )

    # Update aggregated stats
    update_aggregated_stats(method_name, endpoint, solution_id, table_id)
  rescue => e
    # Silently fail - stats tracking should never interrupt user work
    warn "Stats tracking failed: #{e.message}" if ENV['DEBUG']
  end

  def get_stats(time_range: 'all')
    # Validate time_range parameter
    valid_ranges = ['session', '7d', 'all']
    unless valid_ranges.include?(time_range)
      time_range = 'all'
    end

    # Build time filter SQL
    time_filter = build_time_filter(time_range)

    summary = @db.execute("SELECT * FROM api_stats_summary WHERE user_hash = ?", [@user_hash]).first

    unless summary
      return {
        'time_range' => time_range,
        'summary' => {
          'total_calls' => 0,
          'first_call' => nil,
          'last_call' => nil,
          'unique_users' => 0,
          'unique_solutions' => 0,
          'unique_tables' => 0
        },
        'by_method' => {},
        'by_solution' => {},
        'by_table' => {},
        'by_endpoint' => {},
        'cache_stats' => get_cache_stats(time_filter)
      }
    end

    {
      'time_range' => time_range,
      'summary' => {
        'total_calls' => get_call_count_filtered(time_filter),
        'first_call' => summary['first_call'],
        'last_call' => summary['last_call'],
        'unique_users' => get_unique_count('user_hash', time_filter),
        'unique_solutions' => get_unique_count('solution_id', time_filter),
        'unique_tables' => get_unique_count('table_id', time_filter)
      },
      'by_method' => get_breakdown_by('method', time_filter),
      'by_solution' => get_breakdown_by('solution_id', time_filter),
      'by_table' => get_breakdown_by('table_id', time_filter),
      'by_endpoint' => get_breakdown_by('endpoint', time_filter),
      'cache_stats' => get_cache_stats(time_filter)
    }
  end

  def reset_stats
    @db.execute("DELETE FROM api_call_log WHERE user_hash = ?", [@user_hash])
    @db.execute("DELETE FROM api_stats_summary WHERE user_hash = ?", [@user_hash])

    {
      'status' => 'success',
      'message' => 'API statistics have been reset'
    }
  rescue => e
    {
      'status' => 'error',
      'message' => "Failed to reset stats: #{e.message}"
    }
  end

  def close
    @db.close if @owns_db && @db
  end

  private

  def update_aggregated_stats(method_name, endpoint, solution_id, table_id)
    timestamp = Time.now.utc.iso8601

    # Upsert summary stats
    @db.execute(
      "INSERT INTO api_stats_summary (user_hash, total_calls, first_call, last_call)
       VALUES (?, 1, ?, ?)
       ON CONFLICT(user_hash) DO UPDATE SET
         total_calls = total_calls + 1,
         first_call = COALESCE(first_call, excluded.first_call),
         last_call = excluded.last_call",
      [@user_hash, timestamp, timestamp]
    )
  end

  def build_time_filter(time_range)
    case time_range
    when 'session'
      "AND session_id = '#{@session_id}'"
    when '7d'
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
      [@user_hash]
    ).first

    result ? result['count'] : 0
  end

  def get_unique_count(column, time_filter = "")
    return 0 if column.nil?

    result = @db.execute(
      "SELECT COUNT(DISTINCT #{column}) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL #{time_filter}",
      [@user_hash]
    ).first

    result ? result['count'] : 0
  end

  def get_breakdown_by(column, time_filter = "")
    results = @db.execute(
      "SELECT #{column}, COUNT(*) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL #{time_filter}
       GROUP BY #{column}
       ORDER BY count DESC",
      [@user_hash]
    )

    results.each_with_object({}) do |row, hash|
      hash[row[column]] = row['count']
    end
  end

  def get_cache_stats(time_filter)
    # Query cache_performance table for all tables
    perf_results = @db.execute(
      "SELECT * FROM cache_performance ORDER BY table_id"
    )

    return empty_cache_stats if perf_results.empty?

    # Calculate overall cache metrics
    total_hits = perf_results.sum { |r| r['hit_count'] || 0 }
    total_misses = perf_results.sum { |r| r['miss_count'] || 0 }
    total_operations = total_hits + total_misses

    # Calculate efficiency: cache hits saved API calls
    # Each cache hit = 1+ API calls saved (pagination means 1 miss can = multiple API calls)
    api_calls_made = get_call_count_filtered(time_filter)

    # Estimate API calls that would have been made without cache
    # Conservative estimate: each cache hit saved 1 API call
    api_calls_saved = total_hits
    api_calls_without_cache = api_calls_made + api_calls_saved

    # Calculate hit rate and efficiency ratio
    hit_rate = total_operations > 0 ? (total_hits.to_f / total_operations * 100).round(2) : 0.0
    efficiency_ratio = api_calls_without_cache > 0 ? (api_calls_saved.to_f / api_calls_without_cache * 100).round(2) : 0.0

    # Estimate token savings
    # Conservative: each cache hit saves ~500 tokens (vs API call + response parsing)
    estimated_tokens_saved = total_hits * 500

    # Build per-table breakdown
    by_table = perf_results.map do |row|
      table_total = (row['hit_count'] || 0) + (row['miss_count'] || 0)
      table_hit_rate = table_total > 0 ? ((row['hit_count'] || 0).to_f / table_total * 100).round(2) : 0.0

      {
        'table_id' => row['table_id'],
        'hit_count' => row['hit_count'] || 0,
        'miss_count' => row['miss_count'] || 0,
        'total_operations' => table_total,
        'hit_rate' => table_hit_rate,
        'record_count' => row['record_count'] || 0,
        'cache_size_bytes' => row['cache_size_bytes'] || 0,
        'last_access' => row['last_access_time']
      }
    end

    {
      'summary' => {
        'total_cache_hits' => total_hits,
        'total_cache_misses' => total_misses,
        'total_cache_operations' => total_operations,
        'overall_hit_rate' => hit_rate,
        'api_calls_made' => api_calls_made,
        'api_calls_saved' => api_calls_saved,
        'api_calls_without_cache' => api_calls_without_cache,
        'efficiency_ratio' => efficiency_ratio,
        'estimated_tokens_saved' => estimated_tokens_saved
      },
      'by_table' => by_table
    }
  end

  def empty_cache_stats
    {
      'summary' => {
        'total_cache_hits' => 0,
        'total_cache_misses' => 0,
        'total_cache_operations' => 0,
        'overall_hit_rate' => 0.0,
        'api_calls_made' => 0,
        'api_calls_saved' => 0,
        'api_calls_without_cache' => 0,
        'efficiency_ratio' => 0.0,
        'estimated_tokens_saved' => 0
      },
      'by_table' => []
    }
  end

  def extract_solution_id(endpoint)
    endpoint =~ %r{/solutions/([^/?]+)} ? $1 : nil
  end

  def extract_table_id(endpoint)
    endpoint =~ %r{/applications/([^/?]+)} ? $1 : nil
  end
end

