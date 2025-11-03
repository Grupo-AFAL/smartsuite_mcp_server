require 'json'
require 'digest'
require 'time'

class ApiStatsTracker
  STATS_FILE = File.join(Dir.home, '.smartsuite_mcp_stats.json')

  def initialize(api_key)
    @api_key = api_key
    @stats = load_stats
  end

  def track_api_call(method, endpoint)
    # Increment total calls
    @stats['total_calls'] += 1

    # Track by user (hash the API key for privacy)
    user_hash = Digest::SHA256.hexdigest(@api_key)[0..7]
    @stats['by_user'][user_hash] ||= 0
    @stats['by_user'][user_hash] += 1

    # Track by HTTP method
    method_name = method.to_s.upcase
    @stats['by_method'][method_name] ||= 0
    @stats['by_method'][method_name] += 1

    # Track by endpoint
    @stats['by_endpoint'][endpoint] ||= 0
    @stats['by_endpoint'][endpoint] += 1

    # Extract and track solution/table IDs from endpoint
    extract_ids_from_endpoint(endpoint)

    # Track timestamps
    now = Time.now.iso8601
    @stats['first_call'] ||= now
    @stats['last_call'] = now

    # Save stats to disk
    save_stats
  end

  def get_stats
    {
      'summary' => {
        'total_calls' => @stats['total_calls'],
        'first_call' => @stats['first_call'],
        'last_call' => @stats['last_call'],
        'unique_users' => @stats['by_user'].size,
        'unique_solutions' => @stats['by_solution'].size,
        'unique_tables' => @stats['by_table'].size
      },
      'by_user' => @stats['by_user'].sort_by { |k, v| -v }.to_h,
      'by_method' => @stats['by_method'].sort_by { |k, v| -v }.to_h,
      'by_solution' => @stats['by_solution'].sort_by { |k, v| -v }.to_h,
      'by_table' => @stats['by_table'].sort_by { |k, v| -v }.to_h,
      'by_endpoint' => @stats['by_endpoint'].sort_by { |k, v| -v }.to_h
    }
  end

  def reset_stats
    @stats = initialize_stats
    save_stats
    {
      'status' => 'success',
      'message' => 'API statistics have been reset'
    }
  end

  private

  def load_stats
    if File.exist?(STATS_FILE)
      JSON.parse(File.read(STATS_FILE))
    else
      initialize_stats
    end
  rescue
    # If there's any error loading stats, start fresh
    initialize_stats
  end

  def initialize_stats
    {
      'total_calls' => 0,
      'by_user' => {},
      'by_solution' => {},
      'by_table' => {},
      'by_method' => {},
      'by_endpoint' => {},
      'first_call' => nil,
      'last_call' => nil
    }
  end

  def save_stats
    File.write(STATS_FILE, JSON.pretty_generate(@stats))
  rescue
    # Silently fail if we can't save stats - don't interrupt the user's work
  end

  def extract_ids_from_endpoint(endpoint)
    # Parse endpoint to extract solution and table IDs
    # Endpoints look like:
    #   /applications/ or /applications/[table_id]/...
    #   /solutions/ or /solutions/[solution_id]/...

    # Extract solution ID
    if endpoint =~ %r{/solutions/([^/]+)}
      solution_id = $1
      @stats['by_solution'][solution_id] ||= 0
      @stats['by_solution'][solution_id] += 1
    end

    # Extract table ID (applications are tables)
    if endpoint =~ %r{/applications/([^/]+)}
      table_id = $1
      @stats['by_table'][table_id] ||= 0
      @stats['by_table'][table_id] += 1
    end
  end
end
