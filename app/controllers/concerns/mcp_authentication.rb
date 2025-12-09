# frozen_string_literal: true

# Authentication concern for MCP endpoints
# Supports multiple authentication methods:
# - OAuth 2.0 access tokens (from Claude Desktop)
# - API keys (from Claude Code and other clients)
# - Environment variables (local/standalone mode)
module MCPAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private

  def authenticate!
    if auth_mode == :local
      authenticate_local!
    else
      authenticate_remote!
    end
  end

  def auth_mode
    Rails.application.config.smartsuite_auth_mode
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
    Sentry.capture_exception(e, extra: { ip: request.remote_ip, auth_mode: :local })
    render json: { error: e.message }, status: :unauthorized
  end

  # Remote mode: Authenticate via OAuth token or API key
  # Priority: OAuth token > API key
  def authenticate_remote!
    token = extract_bearer_token

    # Try OAuth token first (from Claude Desktop)
    if (user = authenticate_oauth_token(token))
      @current_user = user
      return
    end

    # Fall back to API key (from Claude Code)
    if (api_key = APIKey.authenticate(token))
      @current_user = api_key.user
      return
    end

    render json: { error: "Invalid or missing authentication" }, status: :unauthorized
  end

  # Authenticate OAuth 2.0 access token
  def authenticate_oauth_token(token)
    return nil if token.blank?

    oauth_token = Doorkeeper::AccessToken.find_by(token: token)
    return nil unless oauth_token&.accessible?

    User.find_by(id: oauth_token.resource_owner_id)
  end

  def extract_bearer_token
    auth_header = request.headers["Authorization"]
    return auth_header.sub(/^Bearer\s+/i, "") if auth_header&.start_with?("Bearer")

    # Also check X-API-Key header as fallback
    request.headers["X-API-Key"]
  end

  def current_user
    @current_user
  end
end
