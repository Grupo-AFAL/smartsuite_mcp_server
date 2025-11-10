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
    timestamp = Time.now.to_i

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

  def get_stats
    summary = @db.execute("SELECT * FROM api_stats_summary WHERE user_hash = ?", [@user_hash]).first

    unless summary
      return {
        'summary' => {
          'total_calls' => 0,
          'first_call' => nil,
          'last_call' => nil,
          'unique_solutions' => 0,
          'unique_tables' => 0
        },
        'by_method' => {},
        'by_solution' => {},
        'by_table' => {},
        'by_endpoint' => {}
      }
    end

    {
      'summary' => {
        'total_calls' => summary['total_calls'],
        'first_call' => summary['first_call'] ? Time.at(summary['first_call']).iso8601 : nil,
        'last_call' => summary['last_call'] ? Time.at(summary['last_call']).iso8601 : nil,
        'unique_users' => 1,  # Currently tracking single user
        'unique_solutions' => get_unique_count('solution_id'),
        'unique_tables' => get_unique_count('table_id')
      },
      'by_method' => get_breakdown_by('method'),
      'by_solution' => get_breakdown_by('solution_id'),
      'by_table' => get_breakdown_by('table_id'),
      'by_endpoint' => get_breakdown_by('endpoint')
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
    timestamp = Time.now.to_i

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

  def get_unique_count(column)
    return 0 if column.nil?

    result = @db.execute(
      "SELECT COUNT(DISTINCT #{column}) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL",
      [@user_hash]
    ).first

    result ? result['count'] : 0
  end

  def get_breakdown_by(column)
    results = @db.execute(
      "SELECT #{column}, COUNT(*) as count
       FROM api_call_log
       WHERE user_hash = ? AND #{column} IS NOT NULL
       GROUP BY #{column}
       ORDER BY count DESC",
      [@user_hash]
    )

    results.each_with_object({}) do |row, hash|
      hash[row[column]] = row['count']
    end
  end

  def extract_solution_id(endpoint)
    endpoint =~ %r{/solutions/([^/?]+)} ? $1 : nil
  end

  def extract_table_id(endpoint)
    endpoint =~ %r{/applications/([^/?]+)} ? $1 : nil
  end
end

