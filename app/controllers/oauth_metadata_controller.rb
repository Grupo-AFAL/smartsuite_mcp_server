# frozen_string_literal: true

# OAuth 2.0 Authorization Server Metadata (RFC 8414)
# Provides discovery endpoint for OAuth clients like Claude Desktop
class OAuthMetadataController < ApplicationController
  # GET /.well-known/oauth-authorization-server
  def show
    render json: {
      issuer: issuer_url,
      authorization_endpoint: "#{issuer_url}/oauth/authorize",
      token_endpoint: "#{issuer_url}/oauth/token",
      registration_endpoint: "#{issuer_url}/oauth/register",
      revocation_endpoint: "#{issuer_url}/oauth/revoke",
      introspection_endpoint: "#{issuer_url}/oauth/introspect",
      scopes_supported: %w[read write],
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
      code_challenge_methods_supported: %w[S256],
      service_documentation: "https://github.com/federalsteinmetz/smartsuite_mcp"
    }
  end

  private

  def issuer_url
    # Use X-Forwarded headers in production (behind reverse proxy)
    if request.headers["X-Forwarded-Host"].present?
      protocol = request.headers["X-Forwarded-Proto"] || "https"
      host = request.headers["X-Forwarded-Host"]
      "#{protocol}://#{host}"
    else
      request.base_url
    end
  end
end
