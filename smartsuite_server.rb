#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'lib/smartsuite_client'
require_relative 'lib/api_stats_tracker'
require_relative 'lib/smartsuite/mcp/tool_registry'
require_relative 'lib/smartsuite/mcp/prompt_registry'
require_relative 'lib/smartsuite/mcp/resource_registry'

# rubocop:disable Metrics/ClassLength
class SmartSuiteServer
  def initialize
    @api_key = ENV.fetch('SMARTSUITE_API_KEY', nil)
    @account_id = ENV.fetch('SMARTSUITE_ACCOUNT_ID', nil)

    raise 'SMARTSUITE_API_KEY environment variable is required' unless @api_key
    raise 'SMARTSUITE_ACCOUNT_ID environment variable is required' unless @account_id

    # Initialize SmartSuite API client (creates its own stats tracker with shared cache database)
    @client = SmartSuiteClient.new(@api_key, @account_id)

    # Open metrics log file
    @metrics_log = File.open(File.join(Dir.home, '.smartsuite_mcp_metrics.log'), 'a')
    @metrics_log.sync = true
  end

  def run
    warn '=' * 60
    warn 'SmartSuite MCP Server starting...'
    warn '=' * 60
    loop do
      input = $stdin.gets
      break unless input

      input = input.strip
      next if input.empty?

      request = JSON.parse(input)

      # Check if this is a notification (no id field)
      # Notifications should not receive responses
      if request['id'].nil?
        warn "\n📩 Notification: #{request['method']}"
        next
      end

      # Log the tool call
      if request['method'] == 'tools/call'
        tool_name = request.dig('params', 'name')
        log_metric('=' * 50)
        log_metric("🔧 #{tool_name}")
      end

      response = handle_request(request)
      $stdout.puts JSON.generate(response)
      $stdout.flush
    rescue JSON::ParserError => e
      warn "JSON Parse Error: #{e.message}"
      # For parse errors, we can't know the request ID, so we must omit id
      error_response = {
        'jsonrpc' => '2.0',
        'error' => {
          'code' => -32_700,
          'message' => "Parse error: #{e.message}"
        }
      }
      $stdout.puts JSON.generate(error_response)
      $stdout.flush
    rescue StandardError => e
      warn "Error: #{e.message}\n#{e.backtrace.join("\n")}"
      # Generic error - we also can't know the request ID
      error_response = {
        'jsonrpc' => '2.0',
        'error' => {
          'code' => -32_603,
          'message' => "Internal error: #{e.message}"
        }
      }
      $stdout.puts JSON.generate(error_response)
      $stdout.flush
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
          'code' => -32_601,
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
               @client.list_solutions(
                 include_activity_data: arguments['include_activity_data'],
                 fields: arguments['fields'],
                 name: arguments['name']
               )
             when 'analyze_solution_usage'
               @client.analyze_solution_usage(
                 days_inactive: arguments['days_inactive'] || 90,
                 min_records: arguments['min_records'] || 10
               )
             when 'list_solutions_by_owner'
               @client.list_solutions_by_owner(
                 arguments['owner_id'],
                 include_activity_data: arguments['include_activity_data']
               )
             when 'get_solution_most_recent_record_update'
               @client.get_solution_most_recent_record_update(arguments['solution_id'])
             when 'list_members'
               @client.list_members(limit: arguments['limit'], offset: arguments['offset'], solution_id: arguments['solution_id'])
             when 'search_member'
               @client.search_member(arguments['query'])
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
                 hydrated: arguments['hydrated']
               )
             when 'get_record'
               @client.get_record(arguments['table_id'], arguments['record_id'])
             when 'create_record'
               @client.create_record(arguments['table_id'], arguments['data'])
             when 'update_record'
               @client.update_record(arguments['table_id'], arguments['record_id'], arguments['data'])
             when 'delete_record'
               @client.delete_record(arguments['table_id'], arguments['record_id'])
             when 'bulk_add_records'
               @client.bulk_add_records(arguments['table_id'], arguments['records'])
             when 'bulk_update_records'
               @client.bulk_update_records(arguments['table_id'], arguments['records'])
             when 'bulk_delete_records'
               @client.bulk_delete_records(arguments['table_id'], arguments['record_ids'])
             when 'get_file_url'
               @client.get_file_url(arguments['file_handle'])
             when 'list_deleted_records'
               @client.list_deleted_records(arguments['solution_id'], preview: arguments['preview'])
             when 'restore_deleted_record'
               @client.restore_deleted_record(arguments['table_id'], arguments['record_id'])
             when 'attach_file'
               @client.attach_file(
                 arguments['table_id'],
                 arguments['record_id'],
                 arguments['file_field_slug'],
                 arguments['file_urls']
               )
             when 'add_field'
               @client.add_field(
                 arguments['table_id'],
                 arguments['field_data'],
                 field_position: arguments['field_position'],
                 auto_fill_structure_layout: arguments['auto_fill_structure_layout'].nil? || arguments['auto_fill_structure_layout']
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
               @client.stats_tracker.get_stats(time_range: arguments['time_range'] || 'all')
             when 'reset_api_stats'
               @client.stats_tracker.reset_stats
             when 'get_cache_status'
               if @client.cache_enabled?
                 @client.cache.get_cache_status(table_id: arguments['table_id'])
               else
                 { 'error' => 'Cache is disabled' }
               end
             when 'refresh_cache'
               if @client.cache_enabled?
                 @client.cache.refresh_cache(
                   arguments['resource'],
                   table_id: arguments['table_id'],
                   solution_id: arguments['solution_id']
                 )
               else
                 { 'error' => 'Cache is disabled' }
               end
             when 'warm_cache'
               @client.warm_cache(
                 tables: arguments['tables'],
                 count: arguments['count'] || 5
               )
             else
               return {
                 'jsonrpc' => '2.0',
                 'id' => request['id'],
                 'error' => {
                   'code' => -32_602,
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
  rescue StandardError => e
    {
      'jsonrpc' => '2.0',
      'id' => request['id'],
      'error' => {
        'code' => -32_603,
        'message' => "Tool execution failed: #{e.message}"
      }
    }
  end

  def send_error(message, id)
    response = {
      'jsonrpc' => '2.0',
      'id' => id,
      'error' => {
        'code' => -32_603,
        'message' => message
      }
    }
    $stdout.puts JSON.generate(response)
    $stdout.flush
  end

  def log_metric(message)
    timestamp = Time.now.strftime('%H:%M:%S')
    @metrics_log.puts "[#{timestamp}] #{message}"
  end
end
# rubocop:enable Metrics/ClassLength

if __FILE__ == $PROGRAM_NAME
  server = SmartSuiteServer.new
  server.run
end
