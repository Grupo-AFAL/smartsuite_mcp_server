Rails.application.routes.draw do
  # MCP Streamable HTTP transport endpoints
  # POST /mcp - Handle JSON-RPC messages
  # GET /mcp - SSE stream for server-initiated messages (optional)
  post "mcp", to: "mcp#messages"
  get "mcp", to: "mcp#stream"

  # Installation page and scripts
  get "install", to: "install#show"
  get "install.sh", to: "install#script_sh"
  get "install.ps1", to: "install#script_ps1"

  # Health check for load balancers and Kamal
  get "up" => "rails/health#show", as: :rails_health_check

  # Silence Action Cable connection attempts (disabled in this API-only app)
  # These requests come from browser dev tools or extensions
  get "cable", to: proc { [ 204, {}, [] ] }
end
