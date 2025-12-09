# frozen_string_literal: true

# Authentication concern for MCP endpoints
# Supports two modes configured via AUTH_MODE env var:
# - "remote": API key authentication via database (multi-user hosted mode)
# - "local": Environment variable authentication (single-user standalone mode)
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

  # Remote mode: Authenticate via API key in database
  # Used for multi-user hosted deployments
  def authenticate_remote!
    token = extract_bearer_token
    api_key = APIKey.authenticate(token)

    unless api_key
      render json: { error: "Invalid or missing API key" }, status: :unauthorized
      return
    end

    @current_user = api_key.user
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
