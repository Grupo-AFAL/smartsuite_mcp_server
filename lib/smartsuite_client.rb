require 'json'
require 'net/http'
require 'uri'

class SmartSuiteClient
  API_BASE_URL = 'https://app.smartsuite.com/api/v1'

  def initialize(api_key, account_id, stats_tracker: nil)
    @api_key = api_key
    @account_id = account_id
    @stats_tracker = stats_tracker
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
      { 'tables' => tables, 'count' => tables.size }
    else
      # Return raw response if structure is unexpected
      response
    end
  end

  def list_records(table_id, limit = 50, offset = 0, filter: nil, sort: nil, fields: nil)
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

    # Fields to always strip out (very verbose)
    verbose_fields = ['description', 'comments_count', 'ranking', 'application_slug', 'deleted_date']

    # Essential metadata fields to keep
    essential_fields = ['id', 'application_id', 'autonumber', 'title', 'first_created', 'last_updated']

    filtered_items = response['items'].map do |record|
      if fields && !fields.empty?
        # If specific fields requested, only return those + essential fields
        requested_fields = (fields + essential_fields).uniq
        filter_record_fields(record, requested_fields)
      else
        # Apply aggressive default filtering
        filter_record_fields(record, essential_fields, exclude: verbose_fields)
      end
    end

    {
      'items' => filtered_items,
      'total_count' => response['total_count'],
      'count' => filtered_items.size
    }
  end

  def filter_record_fields(record, include_fields = nil, exclude: [])
    return record unless record.is_a?(Hash)

    if include_fields
      # Only include specified fields
      result = {}
      include_fields.each do |field|
        result[field] = truncate_value(record[field]) if record.key?(field)
      end
      # Also include any field that's not in the exclude list and not a verbose field
      record.each do |key, value|
        next if result.key?(key)
        next if exclude.include?(key)
        # Include custom fields (anything not in metadata fields)
        unless ['id', 'application_id', 'autonumber', 'title', 'first_created', 'last_updated',
                'description', 'comments_count', 'ranking', 'application_slug', 'deleted_date'].include?(key)
          result[key] = truncate_value(value)
        end
      end
      result
    else
      # Exclude specified fields
      result = record.dup
      exclude.each { |field| result.delete(field) }
      # Truncate remaining values
      result.transform_values { |v| truncate_value(v) }
    end
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
end
