#!/usr/bin/env ruby

require 'json'
require_relative 'lib/smartsuite_client'
require_relative 'lib/api_stats_tracker'
require_relative 'lib/smartsuite/mcp/tool_registry'
require_relative 'lib/smartsuite/mcp/prompt_registry'
require_relative 'lib/smartsuite/mcp/resource_registry'

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
    SmartSuite::MCP::PromptRegistry.prompts_list(request)
  end

  def handle_prompt_get(request)
    SmartSuite::MCP::PromptRegistry.prompt_get(request)
  end

  def handle_resources_list(request)
    SmartSuite::MCP::ResourceRegistry.resources_list(request)
  end

  def handle_tools_list(request)
    SmartSuite::MCP::ToolRegistry.tools_list(request)
  end

  def handle_tool_call(request)
    tool_name = request.dig('params', 'name')
    arguments = request.dig('params', 'arguments') || {}

    result = case tool_name
    when 'list_solutions'
      @client.list_solutions(include_activity_data: arguments['include_activity_data'])
    when 'analyze_solution_usage'
      @client.analyze_solution_usage(
        days_inactive: arguments['days_inactive'] || 90,
        min_records: arguments['min_records'] || 10
      )
    when 'list_members'
      @client.list_members(arguments['limit'], arguments['offset'], solution_id: arguments['solution_id'])
    when 'list_teams'
      @client.list_teams
    when 'get_team'
      @client.get_team(arguments['team_id'])
    when 'list_tables'
      @client.list_tables(solution_id: arguments['solution_id'], fields: arguments['fields'])
    when 'get_table'
      @client.get_table(arguments['table_id'])
    when 'create_table'
      @client.create_table(
        arguments['solution_id'],
        arguments['name'],
        description: arguments['description'],
        structure: arguments['structure']
      )
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
    when 'delete_record'
      @client.delete_record(arguments['table_id'], arguments['record_id'])
    when 'add_field'
      @client.add_field(
        arguments['table_id'],
        arguments['field_data'],
        field_position: arguments['field_position'],
        auto_fill_structure_layout: arguments['auto_fill_structure_layout'].nil? ? true : arguments['auto_fill_structure_layout']
      )
    when 'bulk_add_fields'
      @client.bulk_add_fields(
        arguments['table_id'],
        arguments['fields'],
        set_as_visible_fields_in_reports: arguments['set_as_visible_fields_in_reports']
      )
    when 'update_field'
      @client.update_field(arguments['table_id'], arguments['slug'], arguments['field_data'])
    when 'delete_field'
      @client.delete_field(arguments['table_id'], arguments['slug'])
    when 'list_comments'
      @client.list_comments(arguments['record_id'])
    when 'add_comment'
      @client.add_comment(
        arguments['table_id'],
        arguments['record_id'],
        arguments['message'],
        arguments['assigned_to']
      )
    when 'get_view_records'
      @client.get_view_records(
        arguments['table_id'],
        arguments['view_id'],
        with_empty_values: arguments['with_empty_values']
      )
    when 'create_view'
      @client.create_view(
        arguments['application'],
        arguments['solution'],
        arguments['label'],
        arguments['view_mode'],
        description: arguments['description'],
        autosave: arguments['autosave'],
        is_locked: arguments['is_locked'],
        is_private: arguments['is_private'],
        is_password_protected: arguments['is_password_protected'],
        order: arguments['order'],
        state: arguments['state'],
        map_state: arguments['map_state'],
        sharing: arguments['sharing']
      )
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
