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

  def list_records(table_id, limit = 50, offset = 0)
    body = {
      limit: limit,
      offset: offset
    }
    api_request(:post, "/applications/#{table_id}/records/list/", body)
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
end
