# frozen_string_literal: true

# Doorkeeper OAuth 2.0 Provider Configuration
# Enables Claude Desktop Custom Connector integration via OAuth authentication
#
# See: https://doorkeeper.gitbook.io/guides for documentation
Doorkeeper.configure do
  orm :active_record

  # Resource owner authentication
  # Finds the currently logged-in user from session
  resource_owner_authenticator do
    User.find_by(id: session[:user_id]) || redirect_to(login_path)
  end

  # Admin access to manage OAuth applications
  admin_authenticator do
    if current_user&.admin?
      current_user
    else
      redirect_to login_path
    end
  end

  # Token expiration settings
  access_token_expires_in 2.hours
  authorization_code_expires_in 10.minutes

  # Enable refresh tokens for long-lived sessions
  use_refresh_token

  # PKCE support for public clients (Claude Desktop)
  # Not forcing PKCE to maintain compatibility, but supporting it
  # force_pkce

  # OAuth scopes
  default_scopes :read
  optional_scopes :write

  # Grant flows enabled for Claude Desktop
  # - authorization_code: Standard OAuth flow with user consent
  # - client_credentials: For server-to-server (not used by Claude)
  # - refresh_token: To refresh expired access tokens
  grant_flows %w[authorization_code refresh_token]

  # Allow HTTP redirect URIs in development (Claude Desktop uses HTTPS in prod)
  force_ssl_in_redirect_uri !Rails.env.development?

  # Skip authorization screen for trusted applications (like Claude)
  # Claude Desktop will always show the consent screen on first auth
  skip_authorization do |_resource_owner, client|
    # Auto-approve for Claude's registered OAuth client
    client.name == "Claude"
  end

  # Use our User model for resource owner
  resource_owner_from_credentials do |_routes|
    user = User.find_by(email: params[:username])
    user if user&.authenticate(params[:password])
  end

  # Custom base controller for OAuth endpoints
  # This enables session middleware needed for OAuth flow
  base_controller "OAuthBaseController"
end
