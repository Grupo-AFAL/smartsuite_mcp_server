# frozen_string_literal: true

# MCP Controller implementing Streamable HTTP transport
# See: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
class MCPController < ApplicationController
  include MCPAuthentication
  include SSEStreaming

  before_action :validate_content_type, only: :messages
  before_action :reset_cache_tracking, only: :messages

  # POST /mcp - Handle JSON-RPC messages
  def messages
    request_body = parse_request_body
    return if performed?

    result, duration_ms = process_request(request_body)
    track_call(request_body, duration_ms)
    render_or_stream(result)
  end

  # GET /mcp - SSE stream for server-initiated messages
  def stream
    maintain_sse_connection
  end

  private

  def parse_request_body
    JSON.parse(request.body.read)
  rescue JSON::ParserError => e
    render json: json_rpc_error(-32700, "Parse error: #{e.message}"), status: :bad_request
    nil
  end

  def process_request(request_body)
    start_time = Time.current
    result = MCPHandler.new(current_user).process(request_body)
    duration_ms = ((Time.current - start_time) * 1000).round
    [ result, duration_ms ]
  end

  def track_call(request_body, duration_ms)
    APICallTracker.new(
      user: current_user,
      request_body: request_body,
      duration_ms: duration_ms
    ).track
  end

  def validate_content_type
    return if request.content_type&.include?("application/json")

    render json: { error: "Content-Type must be application/json" }, status: :unsupported_media_type
  end

  def reset_cache_tracking
    Cache::PostgresLayer.reset_request_cache_status!
  end

  def json_rpc_error(code, message)
    { jsonrpc: "2.0", id: nil, error: { code: code, message: message } }
  end
end
