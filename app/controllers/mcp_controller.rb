# frozen_string_literal: true

# MCP Controller implementing Streamable HTTP transport
# See: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
#
# Supports two authentication modes (configured via AUTH_MODE env var):
# - "remote": API key authentication via database (multi-user hosted mode)
# - "local": Environment variable authentication (single-user standalone mode)
class MCPController < ApplicationController
  include ActionController::Live

  before_action :authenticate!
  before_action :validate_content_type, only: :messages
  before_action :reset_cache_tracking, only: :messages

  # POST /mcp - Handle JSON-RPC messages
  # Supports both JSON and SSE responses based on Accept header
  def messages
    request_body = JSON.parse(request.body.read)

    start_time = Time.current
    handler = MCPHandler.new(current_user)
    result = handler.process(request_body)
    duration_ms = ((Time.current - start_time) * 1000).round

    # Track the API call
    track_api_call(request_body, duration_ms)

    # Check if client accepts SSE
    if accepts_sse?
      stream_response(result)
    else
      render json: result
    end
  rescue JSON::ParserError => e
    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: { code: -32700, message: "Parse error: #{e.message}" }
    }, status: :bad_request
  end

  # GET /mcp - SSE stream for server-initiated messages (optional)
  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    # For now, just keep the connection alive
    # Server-initiated notifications would be sent here
    loop do
      response.stream.write("event: ping\ndata: {}\n\n")
      sleep 30
    end
  rescue ActionController::Live::ClientDisconnected
    # Client disconnected, clean up
  ensure
    response.stream.close
  end

  private

  def auth_mode
    Rails.application.config.smartsuite_auth_mode
  end

  def authenticate!
    if auth_mode == :local
      authenticate_local!
    else
      authenticate_remote!
    end
  end

  # Local mode: Use environment variables for SmartSuite credentials
  # No API key required - useful for single-user standalone deployments
  def authenticate_local!
    unless LocalUser.env_configured?
      render json: { error: "SMARTSUITE_API_KEY and SMARTSUITE_ACCOUNT_ID environment variables required" },
             status: :unauthorized
      return
    end

    @current_user = LocalUser.from_env
  rescue StandardError => e
    render json: { error: e.message }, status: :unauthorized
  end

  # Remote mode: Authenticate via API key in database
  # Used for multi-user hosted deployments
  def authenticate_remote!
    token = extract_token
    api_key = APIKey.authenticate(token)

    unless api_key
      render json: { error: "Invalid or missing API key" }, status: :unauthorized
      return
    end

    @current_user = api_key.user
  end

  def extract_token
    auth_header = request.headers["Authorization"]
    return auth_header.sub(/^Bearer\s+/i, "") if auth_header&.start_with?("Bearer")

    # Also check X-API-Key header as fallback
    request.headers["X-API-Key"]
  end

  def current_user
    @current_user
  end

  def validate_content_type
    return if request.content_type&.include?("application/json")

    render json: { error: "Content-Type must be application/json" }, status: :unsupported_media_type
  end

  def accepts_sse?
    accept = request.headers["Accept"] || ""
    accept.include?("text/event-stream")
  end

  def stream_response(result)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    response.stream.write("event: message\ndata: #{result.to_json}\n\n")
    response.stream.close
  end

  def track_api_call(request_body, duration_ms)
    return unless request_body["method"] == "tools/call"
    return unless current_user

    # Skip database tracking in local mode (LocalUser doesn't persist)
    return if current_user.is_a?(LocalUser)

    tool_name = request_body.dig("params", "name")
    table_id = extract_table_id(request_body)
    solution_id = extract_solution_id(request_body)

    # If no solution_id in args but we have table_id, look it up from cache
    if solution_id.nil? && table_id
      solution_id = lookup_solution_id_for_table(table_id)
    end

    # Get cache hit status from thread-local tracking in PostgresLayer
    cache_hit = Cache::PostgresLayer.cache_hit_for_request?

    APICall.create(
      user: current_user,
      tool_name: tool_name,
      cache_hit: cache_hit,
      solution_id: solution_id,
      table_id: table_id,
      duration_ms: duration_ms
    )
  rescue StandardError => e
    Rails.logger.warn("Failed to track API call: #{e.message}")
  end

  def extract_solution_id(request_body)
    request_body.dig("params", "arguments", "solution_id")
  end

  def extract_table_id(request_body)
    request_body.dig("params", "arguments", "table_id")
  end

  def lookup_solution_id_for_table(table_id)
    # Query the cache_tables table directly for the solution_id
    result = ActiveRecord::Base.connection.select_one(
      ActiveRecord::Base.sanitize_sql_array([
        "SELECT solution_id FROM cache_tables WHERE table_id = ?",
        table_id
      ])
    )
    result&.fetch("solution_id", nil)
  rescue StandardError => e
    Rails.logger.debug("Failed to lookup solution_id for table #{table_id}: #{e.message}")
    nil
  end

  def reset_cache_tracking
    Cache::PostgresLayer.reset_request_cache_status!
  end
end
