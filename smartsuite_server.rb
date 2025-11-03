#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'digest'
require 'time'

class SmartSuiteServer
  API_BASE_URL = 'https://app.smartsuite.com/api/v1'
  STATS_FILE = File.join(Dir.home, '.smartsuite_mcp_stats.json')

  def initialize
    @api_key = ENV['SMARTSUITE_API_KEY']
    @account_id = ENV['SMARTSUITE_ACCOUNT_ID']

    raise "SMARTSUITE_API_KEY environment variable is required" unless @api_key
    raise "SMARTSUITE_ACCOUNT_ID environment variable is required" unless @account_id

    # Initialize or load API call statistics
    @stats = load_stats
  end

  def run
    $stderr.puts "SmartSuite MCP Server starting..."
    loop do
      begin
        input = STDIN.gets
        break unless input

        input = input.strip
        next if input.empty?

        request = JSON.parse(input)

        # Check if this is a notification (no id field)
        # Notifications should not receive responses
        if request['id'].nil?
          $stderr.puts "Received notification: #{request['method']}"
          next
        end

        response = handle_request(request)
        STDOUT.puts JSON.generate(response)
        STDOUT.flush
      rescue JSON::ParserError => e
        $stderr.puts "JSON Parse Error: #{e.message}"
        # For parse errors, we can't know the request ID, so we must omit id
        error_response = {
          'jsonrpc' => '2.0',
          'error' => {
            'code' => -32700,
            'message' => "Parse error: #{e.message}"
          }
        }
        STDOUT.puts JSON.generate(error_response)
        STDOUT.flush
      rescue => e
        $stderr.puts "Error: #{e.message}\n#{e.backtrace.join("\n")}"
        # Generic error - we also can't know the request ID
        error_response = {
          'jsonrpc' => '2.0',
          'error' => {
            'code' => -32603,
            'message' => "Internal error: #{e.message}"
          }
        }
        STDOUT.puts JSON.generate(error_response)
        STDOUT.flush
      end
    end
  end

  private

  def handle_request(request)
    method = request['method']

    case method
    when 'initialize'
      handle_initialize(request)
    when 'tools/list'
      handle_tools_list(request)
    when 'tools/call'
      handle_tool_call(request)
    when 'prompts/list'
      handle_prompts_list(request)
    when 'resources/list'
      handle_resources_list(request)
    else
      {
        'jsonrpc' => '2.0',
        'id' => request['id'],
        'error' => {
          'code' => -32601,
          'message' => "Method not found: #{method}"
        }
      }
    end
  end

  def handle_initialize(request)
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'protocolVersion' => '2024-11-05',
        'serverInfo' => {
          'name' => 'smartsuite-server',
          'version' => '1.0.1'
        },
        'capabilities' => {
          'tools' => {},
          'prompts' => {},
          'resources' => {}
        }
      }
    }
  end

  def handle_prompts_list(request)
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'prompts' => []
      }
    }
  end

  def handle_resources_list(request)
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'resources' => []
      }
    }
  end

  def handle_tools_list(request)
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'tools' => [
          {
            'name' => 'list_solutions',
            'description' => 'List all solutions in your SmartSuite workspace (solutions contain tables)',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {},
              'required' => []
            }
          },
          {
            'name' => 'list_tables',
            'description' => 'List all tables (apps) in your SmartSuite workspace',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {},
              'required' => []
            }
          },
          {
            'name' => 'list_records',
            'description' => 'List records from a SmartSuite table with optional filtering',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table to query'
                },
                'limit' => {
                  'type' => 'number',
                  'description' => 'Maximum number of records to return (default: 50)'
                },
                'offset' => {
                  'type' => 'number',
                  'description' => 'Number of records to skip (for pagination)'
                }
              },
              'required' => ['table_id']
            }
          },
          {
            'name' => 'get_record',
            'description' => 'Get a specific record by ID from a SmartSuite table',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table'
                },
                'record_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the record to retrieve'
                }
              },
              'required' => ['table_id', 'record_id']
            }
          },
          {
            'name' => 'create_record',
            'description' => 'Create a new record in a SmartSuite table',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table'
                },
                'data' => {
                  'type' => 'object',
                  'description' => 'The record data as key-value pairs (field_slug: value)'
                }
              },
              'required' => ['table_id', 'data']
            }
          },
          {
            'name' => 'update_record',
            'description' => 'Update an existing record in a SmartSuite table',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table'
                },
                'record_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the record to update'
                },
                'data' => {
                  'type' => 'object',
                  'description' => 'The record data to update as key-value pairs (field_slug: value)'
                }
              },
              'required' => ['table_id', 'record_id', 'data']
            }
          },
          {
            'name' => 'get_api_stats',
            'description' => 'Get API call statistics tracked by user, solution, table, and HTTP method',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {},
              'required' => []
            }
          },
          {
            'name' => 'reset_api_stats',
            'description' => 'Reset all API call statistics',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {},
              'required' => []
            }
          }
        ]
      }
    }
  end

  def handle_tool_call(request)
    tool_name = request.dig('params', 'name')
    arguments = request.dig('params', 'arguments') || {}

    result = case tool_name
    when 'list_solutions'
      list_solutions
    when 'list_tables'
      list_tables
    when 'list_records'
      list_records(arguments['table_id'], arguments['limit'], arguments['offset'])
    when 'get_record'
      get_record(arguments['table_id'], arguments['record_id'])
    when 'create_record'
      create_record(arguments['table_id'], arguments['data'])
    when 'update_record'
      update_record(arguments['table_id'], arguments['record_id'], arguments['data'])
    when 'get_api_stats'
      get_api_stats
    when 'reset_api_stats'
      reset_api_stats
    else
      return {
        'jsonrpc' => '2.0',
        'id' => request['id'],
        'error' => {
          'code' => -32602,
          'message' => "Unknown tool: #{tool_name}"
        }
      }
    end

    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'content' => [
          {
            'type' => 'text',
            'text' => JSON.pretty_generate(result)
          }
        ]
      }
    }
  rescue => e
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'error' => {
        'code' => -32603,
        'message' => "Tool execution failed: #{e.message}"
      }
    }
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
    response = api_request(:post, "/applications/#{table_id}/records/list/", body)
    response
  end

  def get_record(table_id, record_id)
    response = api_request(:get, "/applications/#{table_id}/records/#{record_id}/")
    response
  end

  def create_record(table_id, data)
    response = api_request(:post, "/applications/#{table_id}/records/", data)
    response
  end

  def update_record(table_id, record_id, data)
    response = api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)
    response
  end

  def api_request(method, endpoint, body = nil)
    # Track the API call before making it
    track_api_call(method, endpoint)

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

  # API Statistics tracking methods

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

  def get_api_stats
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

  def reset_api_stats
    @stats = initialize_stats
    save_stats
    {
      'status' => 'success',
      'message' => 'API statistics have been reset'
    }
  end

  def send_error(message, id)
    response = {
      'jsonrpc' => '2.0',
      'id' => id,
      'error' => {
        'code' => -32603,
        'message' => message
      }
    }
    STDOUT.puts JSON.generate(response)
    STDOUT.flush
  end
end

if __FILE__ == $0
  server = SmartSuiteServer.new
  server.run
end
