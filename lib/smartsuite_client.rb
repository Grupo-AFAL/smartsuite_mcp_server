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

    # Token usage tracking
    @total_tokens_used = 0
    @context_limit = 200000  # Claude's context window
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
      result = { 'solutions' => solutions, 'count' => solutions.size }
      tokens = estimate_tokens(JSON.generate(result))
      log_metric("✓ Found #{solutions.size} solutions")
      log_token_usage(tokens)
      result
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
      result = { 'solutions' => solutions, 'count' => solutions.size }
      tokens = estimate_tokens(JSON.generate(result))
      log_metric("✓ Found #{solutions.size} solutions")
      log_token_usage(tokens)
      result
    else
      # Return raw response if structure is unexpected
      response
    end
  end

  def list_tables(solution_id: nil)
    # Build endpoint with query parameter if solution_id is provided
    endpoint = '/applications/'
    if solution_id
      endpoint += "?solution=#{solution_id}"
      log_metric("→ Filtering tables by solution: #{solution_id}")
    end

    response = api_request(:get, endpoint)

    # Extract only essential fields to reduce response size
    if response.is_a?(Hash) && response['items'].is_a?(Array)
      tables = response['items'].map do |table|
        {
          'id' => table['id'],
          'name' => table['name'],
          'solution_id' => table['solution_id']
        }
      end

      result = { 'tables' => tables, 'count' => tables.size }
      tokens = estimate_tokens(JSON.generate(result))
      log_metric("✓ Found #{tables.size} tables")
      log_token_usage(tokens)
      result
    elsif response.is_a?(Array)
      # If response is directly an array
      tables = response.map do |table|
        {
          'id' => table['id'],
          'name' => table['name'],
          'solution_id' => table['solution_id']
        }
      end

      result = { 'tables' => tables, 'count' => tables.size }
      tokens = estimate_tokens(JSON.generate(result))
      log_metric("✓ Found #{tables.size} tables")
      log_token_usage(tokens)
      result
    else
      # Return raw response if structure is unexpected
      response
    end
  end

  def get_table(table_id)
    log_metric("→ Getting table structure: #{table_id}")
    response = api_request(:get, "/applications/#{table_id}/")

    # Return filtered structure including only essential fields
    if response.is_a?(Hash)
      # Calculate original size for comparison
      original_structure_json = JSON.generate(response['structure'])
      original_tokens = estimate_tokens(original_structure_json)

      # Filter structure to only essential fields
      filtered_structure = response['structure'].map { |field| filter_field_structure(field) }

      result = {
        'id' => response['id'],
        'name' => response['name'],
        'solution_id' => response['solution_id'],
        'structure' => filtered_structure
      }

      tokens = estimate_tokens(JSON.generate(result))
      reduction_percent = ((original_tokens - tokens).to_f / original_tokens * 100).round(1)

      log_metric("✓ Retrieved table structure: #{filtered_structure.length} fields")
      log_metric("📊 #{original_tokens} → #{tokens} tokens (saved #{reduction_percent}%)")
      log_token_usage(tokens)
      result
    else
      response
    end
  end

  def list_records(table_id, limit = 5, offset = 0, filter: nil, sort: nil, fields: nil, summary_only: false, full_content: false)
    # VALIDATION: Require fields or summary_only to prevent excessive context usage
    if !summary_only && (!fields || fields.empty?)
      error_msg = "ERROR: You must specify 'fields' or use 'summary_only: true'\n\n" +
                  "Correct examples:\n" +
                  "  list_records(table_id, fields: ['status', 'priority'])\n" +
                  "  list_records(table_id, summary_only: true)\n\n" +
                  "This prevents excessive context consumption."
      return {'error' => error_msg}
    end

    # LIMIT: Without filter, maximum 2 records to prevent excessive usage
    if !filter && limit > 2
      log_metric("⚠️  No filter: limit reduced from #{limit} → 2")
      limit = 2
    end

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
    # Returns plain text format to save ~40% tokens vs JSON
    filter_records_response(response, fields, plain_text: true, full_content: full_content)
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

  def filter_field_structure(field)
    # Extract only essential field information
    filtered = {
      'slug' => field['slug'],
      'label' => field['label'],
      'field_type' => field['field_type']
    }

    # Only include essential params if params exist
    return filtered unless field['params']

    params = {}

    # Always include these if present
    params['primary'] = true if field['params']['primary']
    params['required'] = field['params']['required'] unless field['params']['required'].nil?
    params['unique'] = field['params']['unique'] unless field['params']['unique'].nil?

    # For choice fields (status, single select, multi select), strip down choices to only label and value
    if field['params']['choices']
      params['choices'] = field['params']['choices'].map do |choice|
        {'label' => choice['label'], 'value' => choice['value']}
      end
    end

    # For linked record fields, include target table and cardinality
    if field['params']['linked_application']
      params['linked_application'] = field['params']['linked_application']
      params['entries_allowed'] = field['params']['entries_allowed'] if field['params']['entries_allowed']
    end

    filtered['params'] = params unless params.empty?
    filtered
  end

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

  def filter_records_response(response, fields, plain_text: false, full_content: false)
    return response unless response.is_a?(Hash) && response['items'].is_a?(Array)

    # Calculate original size in tokens (approximate)
    original_json = JSON.generate(response)
    original_tokens = estimate_tokens(original_json)

    filtered_items = response['items'].map do |record|
      if fields && !fields.empty?
        # If specific fields requested, only return those + id/title
        requested_fields = (fields + ['id', 'title']).uniq
        filter_record_fields(record, requested_fields, full_content: full_content)
      else
        # Default: only id and title (minimal context usage)
        filter_record_fields(record, ['id', 'title'], full_content: full_content)
      end
    end

    # Format as plain text to save ~40% tokens vs JSON
    if plain_text
      result_text = format_as_plain_text(filtered_items, response['total_count'], full_content: full_content)
      tokens = estimate_tokens(result_text)
      reduction_percent = ((original_tokens - tokens).to_f / original_tokens * 100).round(1)

      content_mode = full_content ? "full content" : "truncated"
      log_metric("✓ Found #{filtered_items.size} records (plain text, #{content_mode})")
      log_metric("📊 #{original_tokens} → #{tokens} tokens (saved #{reduction_percent}%)")
      log_token_usage(tokens)

      return result_text
    end

    # JSON format (for backward compatibility)
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
    log_token_usage(filtered_tokens)

    result
  end

  def estimate_tokens(text)
    # More accurate approximation for JSON:
    # - Each character is ~1 token due to structure (brackets, quotes, commas)
    # - Using 1.5 chars per token is more realistic for JSON
    # This tends to OVERESTIMATE slightly, which is safer than underestimating
    (text.length / 1.5).round
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

    result = {
      'summary': summary_lines.join("\n"),
      'count': items.size,
      'total_count': total,
      'fields_analyzed': field_stats.keys
    }

    tokens = estimate_tokens(JSON.generate(result))
    log_metric("✓ Summary: #{items.size} records analyzed")
    log_metric("📊 Minimal context (summary mode)")
    log_token_usage(tokens)

    result
  end

  def format_as_plain_text(records, total_count, full_content: false)
    return "No records found." if records.empty?

    lines = []
    lines << "Found #{records.size} records (total: #{total_count || records.size})"
    lines << ""

    records.each_with_index do |record, index|
      lines << "Record #{index + 1}:"
      record.each do |key, value|
        # Format value appropriately - values are already truncated by truncate_value if needed
        # We don't truncate again here (removed the 100-char limit)
        formatted_value = case value
        when Hash
          value.inspect # No truncation - already handled
        when Array
          value.join(", ") # No truncation - already handled
        else
          value.to_s
        end
        lines << "  #{key}: #{formatted_value}"
      end
      lines << ""
    end

    lines.join("\n")
  end

  def filter_record_fields(record, include_fields, full_content: false)
    return record unless record.is_a?(Hash)

    # Only include specified fields
    result = {}
    include_fields.each do |field|
      result[field] = truncate_value(record[field], full_content: full_content) if record.key?(field)
    end
    result
  end

  def truncate_value(value, full_content: false)
    # If full_content is true, return value as-is (no truncation)
    return value if full_content

    # Default behavior: truncate to 500 chars for safety
    case value
    when String
      value.length > 500 ? value[0...500] + '... [truncated]' : value
    when Hash
      # For nested hashes (like description), truncate aggressively
      if value['html'] || value['data'] || value['yjsData']
        # This is likely a rich text field - just keep preview
        value['preview'] ? value['preview'][0...500] : '[Rich text content]'
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

  def log_token_usage(tokens_used)
    @total_tokens_used += tokens_used
    usage_percent = (@total_tokens_used.to_f / @context_limit * 100).round(1)
    remaining = @context_limit - @total_tokens_used

    log_metric("📈 Total usado: #{@total_tokens_used} tokens (#{usage_percent}%) | Quedan: #{remaining}")
  end
end
