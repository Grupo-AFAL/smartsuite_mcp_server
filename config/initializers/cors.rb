# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow all origins for MCP clients (Claude Code, etc.)
    # In production, you may want to restrict this to specific origins
    origins "*"

    resource "/mcp",
             headers: :any,
             methods: %i[get post options],
             expose: %w[Content-Type X-Request-Id],
             max_age: 600

    resource "/up",
             headers: :any,
             methods: [ :get ]
  end
end
