# frozen_string_literal: true

require_relative "../../lib/smart_suite_client"
require_relative "../../lib/smart_suite/mcp/tool_registry"
require_relative "../../lib/smart_suite/mcp/prompt_registry"
require_relative "../../lib/smart_suite/mcp/resource_registry"
require_relative "../../lib/smart_suite/formatters/markdown_to_smartdoc"

# MCP message handler for the Rails hosted server
# Each user gets their own SmartSuiteClient with their credentials
# but shares the PostgreSQL cache across all users
class MCPHandler
  # Shared cache instance for all users (thread-safe via PostgreSQL)
  def self.shared_cache
    @shared_cache ||= ::Cache::PostgresLayer.new
  end

  # Shared client instances per user (keyed by user ID)
  # This ensures consistent session IDs across requests in a conversation
  def self.client_for_user(user)
    @clients ||= {}
    user_key = user.respond_to?(:id) ? user.id : user.object_id

    @clients[user_key] ||= SmartSuiteClient.new(
      user.smartsuite_api_key,
      user.smartsuite_account_id,
      cache: shared_cache
    )
  end

  # Clear client cache (useful for testing or when user credentials change)
  def self.reset_clients!
    @clients = {}
  end

  def initialize(user)
    @user = user
    @client = self.class.client_for_user(user)
    @timezone_configured = false
  end

  def process(request)
    method = request["method"]
    id = request["id"]

    result = case method
    when "initialize"
      handle_initialize
    when "tools/list"
      handle_tools_list(request)
    when "tools/call"
      handle_tool_call(request)
    when "prompts/list"
      handle_prompts_list(request)
    when "prompts/get"
      handle_prompt_get(request)
    when "resources/list"
      handle_resources_list(request)
    else
      return error_response(id, -32_601, "Method not found: #{method}")
    end

    result.merge("id" => id)
  rescue StandardError => e
    Rails.logger.error("MCP Handler error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    error_response(id, -32_603, "Internal error: #{e.message}")
  end

  private

  def handle_initialize
    {
      "jsonrpc" => "2.0",
      "result" => {
        "protocolVersion" => "2024-11-05",
        "serverInfo" => {
          "name" => "smartsuite-server",
          "version" => "2.0.0-hosted"
        },
        "capabilities" => {
          "tools" => {},
          "prompts" => {},
          "resources" => {}
        }
      }
    }
  end

  def handle_tools_list(request)
    SmartSuite::MCP::ToolRegistry.tools_list(request)
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

  # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
  def handle_tool_call(request)
    configure_timezone_once

    tool_name = request.dig("params", "name")
    arguments = request.dig("params", "arguments") || {}

    result = execute_tool(tool_name, arguments)

    return result if result.is_a?(Hash) && result["error"]

    # Format result - if already a string (TOON format), use as-is
    result_text = result.is_a?(String) ? result : JSON.pretty_generate(result)

    {
      "jsonrpc" => "2.0",
      "result" => {
        "content" => [
          {
            "type" => "text",
            "text" => result_text
          }
        ]
      }
    }
  rescue StandardError => e
    Rails.logger.error("Tool execution failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    error_response(request["id"], -32_603, "Tool execution failed: #{e.message}")
  end

  def execute_tool(tool_name, arguments)
    case tool_name
    when "list_solutions"
      @client.list_solutions(
        include_activity_data: arguments["include_activity_data"],
        fields: arguments["fields"],
        name: arguments["name"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "analyze_solution_usage"
      @client.analyze_solution_usage(
        days_inactive: arguments["days_inactive"] || 90,
        min_records: arguments["min_records"] || 10
      )
    when "list_solutions_by_owner"
      @client.list_solutions_by_owner(
        arguments["owner_id"],
        include_activity_data: arguments["include_activity_data"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "get_solution_most_recent_record_update"
      @client.get_solution_most_recent_record_update(arguments["solution_id"])
    when "list_members"
      @client.list_members(**{
        limit: arguments["limit"],
        offset: arguments["offset"],
        solution_id: arguments["solution_id"],
        include_inactive: arguments["include_inactive"],
        format: (arguments["format"] || "toon").to_sym
      }.compact)
    when "search_member"
      @client.search_member(
        arguments["query"],
        include_inactive: arguments["include_inactive"] || false,
        format: (arguments["format"] || "toon").to_sym
      )
    when "list_teams"
      @client.list_teams(format: (arguments["format"] || "toon").to_sym)
    when "get_team"
      @client.get_team(arguments["team_id"], format: (arguments["format"] || "toon").to_sym)
    when "list_tables"
      @client.list_tables(
        solution_id: arguments["solution_id"],
        fields: arguments["fields"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "get_table"
      @client.get_table(arguments["table_id"], format: (arguments["format"] || "toon").to_sym)
    when "create_table"
      @client.create_table(
        arguments["solution_id"],
        arguments["name"],
        description: arguments["description"],
        structure: arguments["structure"]
      )
    when "list_records"
      @client.list_records(
        arguments["table_id"],
        arguments["limit"],
        arguments["offset"],
        filter: arguments["filter"],
        sort: arguments["sort"],
        fields: arguments["fields"],
        hydrated: arguments["hydrated"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "get_record"
      @client.get_record(arguments["table_id"], arguments["record_id"], format: (arguments["format"] || "toon").to_sym)
    when "create_record"
      @client.create_record(
        arguments["table_id"],
        arguments["data"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "update_record"
      @client.update_record(
        arguments["table_id"],
        arguments["record_id"],
        arguments["data"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "delete_record"
      @client.delete_record(
        arguments["table_id"],
        arguments["record_id"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "bulk_add_records"
      @client.bulk_add_records(
        arguments["table_id"],
        arguments["records"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "bulk_update_records"
      @client.bulk_update_records(
        arguments["table_id"],
        arguments["records"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "bulk_delete_records"
      @client.bulk_delete_records(
        arguments["table_id"],
        arguments["record_ids"],
        minimal_response: arguments.key?("minimal_response") ? arguments["minimal_response"] : true
      )
    when "get_file_url"
      @client.get_file_url(arguments["file_handle"])
    when "list_deleted_records"
      @client.list_deleted_records(
        arguments["solution_id"],
        full_data: arguments["full_data"] || false,
        format: (arguments["format"] || "toon").to_sym
      )
    when "restore_deleted_record"
      @client.restore_deleted_record(arguments["table_id"], arguments["record_id"], format: (arguments["format"] || "toon").to_sym)
    when "attach_file"
      @client.attach_file(
        arguments["table_id"],
        arguments["record_id"],
        arguments["file_field_slug"],
        arguments["file_urls"]
      )
    when "add_field"
      @client.add_field(
        arguments["table_id"],
        arguments["field_data"],
        field_position: arguments["field_position"],
        auto_fill_structure_layout: arguments["auto_fill_structure_layout"].nil? || arguments["auto_fill_structure_layout"]
      )
    when "bulk_add_fields"
      @client.bulk_add_fields(
        arguments["table_id"],
        arguments["fields"],
        set_as_visible_fields_in_reports: arguments["set_as_visible_fields_in_reports"]
      )
    when "update_field"
      @client.update_field(arguments["table_id"], arguments["slug"], arguments["field_data"])
    when "delete_field"
      @client.delete_field(arguments["table_id"], arguments["slug"])
    when "list_comments"
      @client.list_comments(
        arguments["record_id"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "add_comment"
      @client.add_comment(
        arguments["table_id"],
        arguments["record_id"],
        arguments["message"],
        arguments["assigned_to"]
      )
    when "get_view_records"
      @client.get_view_records(
        arguments["table_id"],
        arguments["view_id"],
        with_empty_values: arguments["with_empty_values"],
        format: (arguments["format"] || "toon").to_sym
      )
    when "create_view"
      @client.create_view(
        arguments["application"],
        arguments["solution"],
        arguments["label"],
        arguments["view_mode"],
        description: arguments["description"],
        autosave: arguments["autosave"],
        is_locked: arguments["is_locked"],
        is_private: arguments["is_private"],
        is_password_protected: arguments["is_password_protected"],
        order: arguments["order"],
        state: arguments["state"],
        map_state: arguments["map_state"],
        sharing: arguments["sharing"]
      )
    when "get_api_stats"
      # In hosted mode, use Rails APICall model instead of stats_tracker
      get_api_stats_from_rails(arguments["time_range"] || "all")
    when "reset_api_stats"
      # In hosted mode, use Rails APICall model
      reset_api_stats_in_rails
    when "get_cache_status"
      if @client.cache_enabled?
        @client.cache.get_cache_status(table_id: arguments["table_id"])
      else
        { "error" => "Cache is disabled" }
      end
    when "refresh_cache"
      if @client.cache_enabled?
        @client.cache.refresh_cache(
          arguments["resource"],
          table_id: arguments["table_id"],
          solution_id: arguments["solution_id"]
        )
      else
        { "error" => "Cache is disabled" }
      end
    when "convert_markdown_to_smartdoc"
      SmartSuite::Formatters::MarkdownToSmartdoc.convert(arguments["markdown"])
    else
      error_response(nil, -32_602, "Unknown tool: #{tool_name}")
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize

  def configure_timezone_once
    return if @timezone_configured

    @timezone_configured = true
    @client.configure_user_timezone
  rescue StandardError => e
    Rails.logger.warn("Failed to configure timezone: #{e.message}")
  end

  def error_response(id, code, message)
    {
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => {
        "code" => code,
        "message" => message
      }
    }
  end

  # Get API stats from Rails APICall model (hosted mode)
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def get_api_stats_from_rails(time_range)
    user_id = @user.respond_to?(:id) ? @user.id : nil
    return { "error" => "Stats not available in local mode" } unless user_id

    scope = APICall.where(user_id: user_id)

    # Apply time range filter
    scope = case time_range
    when "today"
      scope.where("created_at >= ?", Time.current.beginning_of_day)
    when "week"
      scope.where("created_at >= ?", 1.week.ago)
    when "month"
      scope.where("created_at >= ?", 1.month.ago)
    else
      scope
    end

    {
      "time_range" => time_range,
      "total_calls" => scope.count,
      "cache_hits" => scope.where(cache_hit: true).count,
      "cache_misses" => scope.where(cache_hit: false).count,
      "by_tool" => scope.group(:tool_name).count,
      "by_table" => scope.where.not(table_id: nil).group(:table_id).count
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Reset API stats in Rails (hosted mode)
  def reset_api_stats_in_rails
    user_id = @user.respond_to?(:id) ? @user.id : nil
    return { "error" => "Stats not available in local mode" } unless user_id

    deleted_count = APICall.where(user_id: user_id).delete_all
    { "success" => true, "deleted_count" => deleted_count }
  end
end
