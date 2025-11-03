require 'json'
require 'net/http'
require 'uri'

class SmartSuiteClient
  API_BASE_URL = 'https://app.smartsuite.com/api/v1'

  def initialize(api_key, account_id, stats_tracker: nil)
    @api_key = api_key
    @account_id = account_id
    @stats_tracker = stats_tracker

    # Create a separate, clean log file for metrics
    @metrics_log = File.open(File.join(Dir.home, '.smartsuite_mcp_metrics.log'), 'a')
    @metrics_log.sync = true  # Auto-flush
  end

  def list_solutions
    response = api_request(:get, '/solutions/')

    # Extract only essential fields to reduce response size
    if response.is_a?(Hash) && response['items'].is_a?(Array)
      solutions = response['items'].map do |solution|
        {
          'id' => solution['id'],
          'name' => solution['name'],
          'logo_icon' => solution['logo_icon'],
          'logo_color' => solution['logo_color']
        }
      end
      log_metric("✓ Found #{solutions.size} solutions")
      { 'solutions' => solutions, 'count' => solutions.size }
    elsif response.is_a?(Array)
      # If response is directly an array
      solutions = response.map do |solution|
        {
          'id' => solution['id'],
          'name' => solution['name'],
          'logo_icon' => solution['logo_icon'],
          'logo_color' => solution['logo_color']
        }
      end
      log_metric("✓ Found #{solutions.size} solutions")
      { 'solutions' => solutions, 'count' => solutions.size }
    else
      # Return raw response if structure is unexpected
      response
    end
  end

  def list_tables
    response = api_request(:get, '/applications/')

    # Extract only essential fields to reduce response size
    if response.is_a?(Hash) && response['items'].is_a?(Array)
      tables = response['items'].map do |table|
        {
          'id' => table['id'],
          'name' => table['name'],
          'solution_id' => table['solution_id']
        }
      end
      log_metric("✓ Found #{tables.size} tables")
      { 'tables' => tables, 'count' => tables.size }
    elsif response.is_a?(Array)
      # If response is directly an array
      tables = response.map do |table|
        {
          'id' => table['id'],
          'name' => table['name'],
          'solution_id' => table['solution_id']
        }
      end
      log_metric("✓ Found #{tables.size} tables")
      { 'tables' => tables, 'count' => tables.size }
    else
      # Return raw response if structure is unexpected
      response
    end
  end

  def list_records(table_id, limit = 5, offset = 0, filter: nil, sort: nil, fields: nil, summary_only: false)
    body = {
      limit: limit,
      offset: offset
    }

    # Add filter if provided
    # Filter format: {"operator": "and|or", "fields": [{"field": "field_slug", "comparison": "operator", "value": "value"}]}
    # Example: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}
    body[:filter] = filter if filter

    # Add sort if provided
    # Sort format: [{"field": "field_slug", "direction": "asc|desc"}]
    # Example: [{"field": "created_on", "direction": "desc"}]
    body[:sort] = sort if sort

    response = api_request(:post, "/applications/#{table_id}/records/list/", body)

    # If summary_only, return just statistics
    if summary_only
      return generate_summary(response)
    end

    # Apply aggressive filtering to reduce response size
    filter_records_response(response, fields)
  end

  def get_record(table_id, record_id)
    api_request(:get, "/applications/#{table_id}/records/#{record_id}/")
  end

  def create_record(table_id, data)
    api_request(:post, "/applications/#{table_id}/records/", data)
  end

  def update_record(table_id, record_id, data)
    api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)
  end

  private

  def api_request(method, endpoint, body = nil)
    # Track the API call if stats tracker is available
    @stats_tracker&.track_api_call(method, endpoint)

    log_metric("→ #{method.upcase} #{endpoint}")

    uri = URI.parse("#{API_BASE_URL}#{endpoint}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = case method
    when :get
      Net::HTTP::Get.new(uri.request_uri)
    when :post
      Net::HTTP::Post.new(uri.request_uri)
    when :patch
      Net::HTTP::Patch.new(uri.request_uri)
    end

    request['Authorization'] = "Token #{@api_key}"
    request['Account-Id'] = @account_id
    request['Content-Type'] = 'application/json'

    if body
      request.body = JSON.generate(body)
    end

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "API request failed: #{response.code} - #{response.body}"
    end

    JSON.parse(response.body)
  end

  def filter_records_response(response, fields)
    return response unless response.is_a?(Hash) && response['items'].is_a?(Array)

    # Calculate original size in tokens (approximate)
    original_json = JSON.generate(response)
    original_tokens = estimate_tokens(original_json)

    filtered_items = response['items'].map do |record|
      if fields && !fields.empty?
        # If specific fields requested, only return those + id/title
        requested_fields = (fields + ['id', 'title']).uniq
        filter_record_fields(record, requested_fields)
      else
        # Default: only id and title (minimal context usage)
        filter_record_fields(record, ['id', 'title'])
      end
    end

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

    result
  end

  def estimate_tokens(text)
    # Rough approximation: 1 token ≈ 4 characters for English text
    # For JSON, it's closer to 1 token per 3-4 bytes
    # Using 3.5 as a reasonable middle ground
    (text.length / 3.5).round
  end

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

    log_metric("✓ Summary: #{items.size} records analyzed")
    log_metric("📊 Minimal context (summary mode)")

    {
      'summary': summary_lines.join("\n"),
      'count': items.size,
      'total_count': total,
      'fields_analyzed': field_stats.keys
    }
  end

  def filter_record_fields(record, include_fields)
    return record unless record.is_a?(Hash)

    # Only include specified fields
    result = {}
    include_fields.each do |field|
      result[field] = truncate_value(record[field]) if record.key?(field)
    end
    result
  end

  def truncate_value(value)
    case value
    when String
      value.length > 500 ? value[0...500] + '... [truncated]' : value
    when Hash
      # For nested hashes (like description), truncate aggressively
      if value['html'] || value['data'] || value['yjsData']
        # This is likely a rich text field - just keep preview
        value['preview'] ? value['preview'][0...200] : '[Rich text content]'
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

  def log_metric(message)
    timestamp = Time.now.strftime('%H:%M:%S')
    @metrics_log.puts "[#{timestamp}] #{message}"
  end
end
