#!/usr/bin/env ruby

require 'json'
require_relative 'lib/smartsuite_client'
require_relative 'lib/api_stats_tracker'

class SmartSuiteServer
  def initialize
    @api_key = ENV['SMARTSUITE_API_KEY']
    @account_id = ENV['SMARTSUITE_ACCOUNT_ID']

    raise "SMARTSUITE_API_KEY environment variable is required" unless @api_key
    raise "SMARTSUITE_ACCOUNT_ID environment variable is required" unless @account_id

    # Initialize API statistics tracker
    @stats_tracker = ApiStatsTracker.new(@api_key)

    # Initialize SmartSuite API client with stats tracker
    @client = SmartSuiteClient.new(@api_key, @account_id, stats_tracker: @stats_tracker)
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
            'description' => 'List records from a SmartSuite table with optional filtering and sorting',
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
                },
                'filter' => {
                  'type' => 'object',
                  'description' => 'Filter criteria with operator and fields array. Example: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}'
                },
                'sort' => {
                  'type' => 'array',
                  'description' => 'Sort criteria as array of field-direction pairs. Example: [{"field": "created_on", "direction": "desc"}]',
                  'items' => {
                    'type' => 'object',
                    'properties' => {
                      'field' => {
                        'type' => 'string',
                        'description' => 'Field slug to sort by'
                      },
                      'direction' => {
                        'type' => 'string',
                        'description' => 'Sort direction: "asc" or "desc"',
                        'enum' => ['asc', 'desc']
                      }
                    }
                  }
                },
                'fields' => {
                  'type' => 'array',
                  'description' => 'Optional: Specific field slugs to return. If not provided, returns essential fields only (id, title, first_created, last_updated) plus custom fields. Reduces response size significantly.',
                  'items' => {
                    'type' => 'string'
                  }
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
      @client.list_solutions
    when 'list_tables'
      @client.list_tables
    when 'list_records'
      @client.list_records(
        arguments['table_id'],
        arguments['limit'],
        arguments['offset'],
        filter: arguments['filter'],
        sort: arguments['sort'],
        fields: arguments['fields']
      )
    when 'get_record'
      @client.get_record(arguments['table_id'], arguments['record_id'])
    when 'create_record'
      @client.create_record(arguments['table_id'], arguments['data'])
    when 'update_record'
      @client.update_record(arguments['table_id'], arguments['record_id'], arguments['data'])
    when 'get_api_stats'
      @stats_tracker.get_stats
    when 'reset_api_stats'
      @stats_tracker.reset_stats
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
