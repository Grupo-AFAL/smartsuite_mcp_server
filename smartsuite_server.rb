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

    # Open metrics log file
    @metrics_log = File.open(File.join(Dir.home, '.smartsuite_mcp_metrics.log'), 'a')
    @metrics_log.sync = true
  end

  def run
    $stderr.puts "=" * 60
    $stderr.puts "SmartSuite MCP Server starting..."
    $stderr.puts "=" * 60
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
          $stderr.puts "\n📩 Notification: #{request['method']}"
          next
        end

        # Log the tool call
        if request['method'] == 'tools/call'
          tool_name = request.dig('params', 'name')
          log_metric("=" * 50)
          log_metric("🔧 #{tool_name}")
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
    when 'prompts/get'
      handle_prompt_get(request)
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
        'prompts' => [
          {
            'name' => 'filter_active_records',
            'description' => 'Example: Filter records where status is "active"',
            'arguments' => [
              {
                'name' => 'table_id',
                'description' => 'The table ID to query',
                'required' => true
              },
              {
                'name' => 'status_field',
                'description' => 'The field slug for status (default: "status")',
                'required' => false
              },
              {
                'name' => 'fields',
                'description' => 'Comma-separated list of field slugs to return',
                'required' => true
              }
            ]
          },
          {
            'name' => 'filter_by_date_range',
            'description' => 'Example: Filter records within a date range',
            'arguments' => [
              {
                'name' => 'table_id',
                'description' => 'The table ID to query',
                'required' => true
              },
              {
                'name' => 'date_field',
                'description' => 'The field slug for the date field',
                'required' => true
              },
              {
                'name' => 'start_date',
                'description' => 'Start date (YYYY-MM-DD format)',
                'required' => true
              },
              {
                'name' => 'end_date',
                'description' => 'End date (YYYY-MM-DD format)',
                'required' => true
              },
              {
                'name' => 'fields',
                'description' => 'Comma-separated list of field slugs to return',
                'required' => true
              }
            ]
          },
          {
            'name' => 'list_tables_by_solution',
            'description' => 'Example: List all tables in a specific solution',
            'arguments' => [
              {
                'name' => 'solution_id',
                'description' => 'The solution ID to filter by',
                'required' => true
              }
            ]
          },
          {
            'name' => 'filter_records_contains_text',
            'description' => 'Example: Filter records where a field contains specific text',
            'arguments' => [
              {
                'name' => 'table_id',
                'description' => 'The table ID to query',
                'required' => true
              },
              {
                'name' => 'field_slug',
                'description' => 'The field slug to search in',
                'required' => true
              },
              {
                'name' => 'search_text',
                'description' => 'The text to search for',
                'required' => true
              },
              {
                'name' => 'fields',
                'description' => 'Comma-separated list of field slugs to return',
                'required' => true
              }
            ]
          }
        ]
      }
    }
  end

  def handle_prompt_get(request)
    prompt_name = request.dig('params', 'name')
    arguments = request.dig('params', 'arguments') || {}

    prompt_text = case prompt_name
    when 'filter_active_records'
      status_field = arguments['status_field'] || 'status'
      fields = arguments['fields']&.split(',')&.map(&:strip) || []

      "Use the list_records tool with these parameters:\n\n" +
      "table_id: #{arguments['table_id']}\n" +
      "fields: #{fields.inspect}\n" +
      "filter: {\n" +
      "  \"operator\": \"and\",\n" +
      "  \"fields\": [\n" +
      "    {\n" +
      "      \"field\": \"#{status_field}\",\n" +
      "      \"comparison\": \"is\",\n" +
      "      \"value\": \"active\"\n" +
      "    }\n" +
      "  ]\n" +
      "}"

    when 'filter_by_date_range'
      date_field = arguments['date_field']
      start_date = arguments['start_date']
      end_date = arguments['end_date']
      fields = arguments['fields']&.split(',')&.map(&:strip) || []

      "Use the list_records tool with these parameters:\n\n" +
      "table_id: #{arguments['table_id']}\n" +
      "fields: #{fields.inspect}\n" +
      "filter: {\n" +
      "  \"operator\": \"and\",\n" +
      "  \"fields\": [\n" +
      "    {\n" +
      "      \"field\": \"#{date_field}\",\n" +
      "      \"comparison\": \"is_after\",\n" +
      "      \"value\": {\n" +
      "        \"date_mode\": \"exact_date\",\n" +
      "        \"date_mode_value\": \"#{start_date}\"\n" +
      "      }\n" +
      "    },\n" +
      "    {\n" +
      "      \"field\": \"#{date_field}\",\n" +
      "      \"comparison\": \"is_before\",\n" +
      "      \"value\": {\n" +
      "        \"date_mode\": \"exact_date\",\n" +
      "        \"date_mode_value\": \"#{end_date}\"\n" +
      "      }\n" +
      "    }\n" +
      "  ]\n" +
      "}"

    when 'list_tables_by_solution'
      "Use the list_tables tool with this parameter:\n\n" +
      "solution_id: #{arguments['solution_id']}\n\n" +
      "This will return only tables from the specified solution."

    when 'filter_records_contains_text'
      field_slug = arguments['field_slug']
      search_text = arguments['search_text']
      fields = arguments['fields']&.split(',')&.map(&:strip) || []

      "Use the list_records tool with these parameters:\n\n" +
      "table_id: #{arguments['table_id']}\n" +
      "fields: #{fields.inspect}\n" +
      "filter: {\n" +
      "  \"operator\": \"and\",\n" +
      "  \"fields\": [\n" +
      "    {\n" +
      "      \"field\": \"#{field_slug}\",\n" +
      "      \"comparison\": \"contains\",\n" +
      "      \"value\": \"#{search_text}\"\n" +
      "    }\n" +
      "  ]\n" +
      "}"

    else
      "Unknown prompt: #{prompt_name}"
    end

    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'result' => {
        'messages' => [
          {
            'role' => 'user',
            'content' => {
              'type' => 'text',
              'text' => prompt_text
            }
          }
        ]
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
            'description' => 'List all tables (apps) in your SmartSuite workspace. Optionally filter by solution_id to only show tables from a specific solution.',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'solution_id' => {
                  'type' => 'string',
                  'description' => 'Optional: Filter tables by solution ID. Use list_solutions first to get solution IDs.'
                }
              },
              'required' => []
            }
          },
          {
            'name' => 'get_table',
            'description' => 'Get a specific table by ID including its structure (fields, their slugs, types, etc). Use this BEFORE querying records to understand what fields are available for filtering and selection.',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table to retrieve'
                }
              },
              'required' => ['table_id']
            }
          },
          {
            'name' => 'list_records',
            'description' => 'List records from a SmartSuite table. DEFAULT: Returns only id + title for minimal context usage. Use fields parameter for specific data or summary_only for statistics.',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'table_id' => {
                  'type' => 'string',
                  'description' => 'The ID of the table to query'
                },
                'limit' => {
                  'type' => 'number',
                  'description' => 'Maximum number of records to return (default: 5 for minimal context usage)'
                },
                'offset' => {
                  'type' => 'number',
                  'description' => 'Number of records to skip (for pagination)'
                },
                'filter' => {
                  'type' => 'object',
                  'description' => 'Filter criteria. STRUCTURE: {"operator": "and|or", "fields": [{"field": "field_slug", "comparison": "operator", "value": "value"}]}. EXAMPLES: 1) Single filter: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}. 2) Multiple filters: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}, {"field": "priority", "comparison": "is_greater_than", "value": 3}]}. 3) Date filter (IMPORTANT - use date value object): {"operator": "and", "fields": [{"field": "due_date", "comparison": "is_after", "value": {"date_mode": "exact_date", "date_mode_value": "2025-01-01"}}]}. OPERATORS: is, is_not, contains, is_greater_than, is_less_than, is_empty, is_not_empty, is_before, is_after. NOTE: Date fields require value as object with date_mode and date_mode_value.'
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
                  'description' => 'Optional: Specific field slugs to return. Default returns only id + title. Specify fields to get additional data.',
                  'items' => {
                    'type' => 'string'
                  }
                },
                'summary_only' => {
                  'type' => 'boolean',
                  'description' => 'If true, returns statistics/summary instead of actual records. Minimal context usage for overview purposes.'
                },
                'full_content' => {
                  'type' => 'boolean',
                  'description' => 'If true, returns full field content without truncation. Default (false): strings truncated to 500 chars. Use when you need complete field values (like full descriptions) to avoid multiple get_record calls.'
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
      @client.list_tables(solution_id: arguments['solution_id'])
    when 'get_table'
      @client.get_table(arguments['table_id'])
    when 'list_records'
      @client.list_records(
        arguments['table_id'],
        arguments['limit'],
        arguments['offset'],
        filter: arguments['filter'],
        sort: arguments['sort'],
        fields: arguments['fields'],
        summary_only: arguments['summary_only'],
        full_content: arguments['full_content']
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

  def log_metric(message)
    timestamp = Time.now.strftime('%H:%M:%S')
    @metrics_log.puts "[#{timestamp}] #{message}"
  end
end

if __FILE__ == $0
  server = SmartSuiteServer.new
  server.run
end
