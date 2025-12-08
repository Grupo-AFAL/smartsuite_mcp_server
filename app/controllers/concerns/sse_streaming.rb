# frozen_string_literal: true

# Server-Sent Events (SSE) streaming support for MCP endpoints
# Handles SSE response format when client requests it via Accept header
module SSEStreaming
  extend ActiveSupport::Concern

  included do
    include ActionController::Live
  end

  private

  def accepts_sse?
    accept_header = request.headers["Accept"] || ""
    accept_header.include?("text/event-stream")
  end

  def render_or_stream(result)
    if accepts_sse?
      stream_sse_response(result)
    else
      render json: result
    end
  end

  def stream_sse_response(result)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    response.stream.write("event: message\ndata: #{result.to_json}\n\n")
    response.stream.close
  end

  # Keep-alive SSE stream for server-initiated messages
  def maintain_sse_connection
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    loop do
      response.stream.write("event: ping\ndata: {}\n\n")
      sleep 30
    end
  rescue ActionController::Live::ClientDisconnected
    # Client disconnected, clean up silently
  ensure
    response.stream.close
  end
end
