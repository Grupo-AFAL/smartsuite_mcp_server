Rails.application.routes.draw do
  # OAuth 2.0 Provider (Doorkeeper)
  use_doorkeeper

  # OAuth Dynamic Client Registration (RFC 7591)
  post "oauth/register", to: "oauth_registrations#create"

  # OAuth Authorization Server Metadata (RFC 8414)
  get ".well-known/oauth-authorization-server", to: "oauth_metadata#show"

  # Authentication routes for OAuth flow
  get "login", to: "sessions#new"
  post "login", to: "sessions#create", as: :sessions
  delete "logout", to: "sessions#destroy"

  # MCP Streamable HTTP transport endpoints
  # POST /mcp - Handle JSON-RPC messages
  # GET /mcp - SSE stream for server-initiated messages (optional)
  post "mcp", to: "mcp#messages"
  get "mcp", to: "mcp#stream"

  # Installation page and scripts
  # Script routes must be defined first with format: false to prevent format matching
  get "install.sh", to: "install#script_sh", format: false
  get "install.ps1", to: "install#script_ps1", format: false
  get "install", to: "install#show"

  # Health check for load balancers and Kamal
  get "up" => "rails/health#show", as: :rails_health_check

  # Root redirects to install page for easy onboarding
  root to: redirect("/install")

  # Silence Action Cable connection attempts (disabled in this API-only app)
  # These requests come from browser dev tools or extensions
  get "cable", to: proc { [ 204, {}, [] ] }
end
