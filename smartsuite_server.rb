#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'

class SmartSuiteServer
  API_BASE_URL = 'https://app.smartsuite.com/api/v1'

  def initialize
    @api_key = ENV['SMARTSUITE_API_KEY']
    @account_id = ENV['SMARTSUITE_ACCOUNT_ID']

    raise "SMARTSUITE_API_KEY environment variable is required" unless @api_key
    raise "SMARTSUITE_ACCOUNT_ID environment variable is required" unless @account_id
  end

  def run
    loop do
      begin
        input = STDIN.gets
        break unless input

        request = JSON.parse(input)
        response = handle_request(request)
        STDOUT.puts JSON.generate(response)
        STDOUT.flush
      rescue JSON::ParserError => e
        send_error("Invalid JSON: #{e.message}")
      rescue => e
        send_error("Error: #{e.message}")
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
    else
      {
        jsonrpc: '2.0',
        id: request['id'],
        error: {
          code: -32601,
          message: "Method not found: #{method}"
        }
      }
    end
  end

  def handle_initialize(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        protocolVersion: '2024-11-05',
        serverInfo: {
          name: 'smartsuite-server',
          version: '1.0.0'
        },
        capabilities: {
          tools: {}
        }
      }
    }
  end

  def handle_tools_list(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        tools: [
          {
            name: 'list_tables',
            description: 'List all tables (apps) in your SmartSuite workspace',
            inputSchema: {
              type: 'object',
              properties: {},
              required: []
            }
          },
          {
            name: 'list_records',
            description: 'List records from a SmartSuite table with optional filtering',
            inputSchema: {
              type: 'object',
              properties: {
                table_id: {
                  type: 'string',
                  description: 'The ID of the table to query'
                },
                limit: {
                  type: 'number',
                  description: 'Maximum number of records to return (default: 50)'
                },
                offset: {
                  type: 'number',
                  description: 'Number of records to skip (for pagination)'
                }
              },
              required: ['table_id']
            }
          },
          {
            name: 'get_record',
            description: 'Get a specific record by ID from a SmartSuite table',
            inputSchema: {
              type: 'object',
              properties: {
                table_id: {
                  type: 'string',
                  description: 'The ID of the table'
                },
                record_id: {
                  type: 'string',
                  description: 'The ID of the record to retrieve'
                }
              },
              required: ['table_id', 'record_id']
            }
          },
          {
            name: 'create_record',
            description: 'Create a new record in a SmartSuite table',
            inputSchema: {
              type: 'object',
              properties: {
                table_id: {
                  type: 'string',
                  description: 'The ID of the table'
                },
                data: {
                  type: 'object',
                  description: 'The record data as key-value pairs (field_slug: value)'
                }
              },
              required: ['table_id', 'data']
            }
          },
          {
            name: 'update_record',
            description: 'Update an existing record in a SmartSuite table',
            inputSchema: {
              type: 'object',
              properties: {
                table_id: {
                  type: 'string',
                  description: 'The ID of the table'
                },
                record_id: {
                  type: 'string',
                  description: 'The ID of the record to update'
                },
                data: {
                  type: 'object',
                  description: 'The record data to update as key-value pairs (field_slug: value)'
                }
              },
              required: ['table_id', 'record_id', 'data']
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
    else
      return {
        jsonrpc: '2.0',
        id: request['id'],
        error: {
          code: -32602,
          message: "Unknown tool: #{tool_name}"
        }
      }
    end

    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        content: [
          {
            type: 'text',
            text: JSON.pretty_generate(result)
          }
        ]
      }
    }
  rescue => e
    {
      jsonrpc: '2.0',
      id: request['id'],
      error: {
        code: -32603,
        message: "Tool execution failed: #{e.message}"
      }
    }
  end

  def list_tables
    response = api_request(:get, '/applications/')
    response
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

  def send_error(message)
    response = {
      jsonrpc: '2.0',
      error: {
        code: -32603,
        message: message
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
