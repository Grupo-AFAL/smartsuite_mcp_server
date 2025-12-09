# OAuth Implementation Plan for Claude Desktop Custom Connectors

This document outlines the requirements and implementation plan for adding OAuth support to the SmartSuite MCP Server, enabling it to work as a native Custom Connector in Claude Desktop.

## Why OAuth?

Currently, our server uses Bearer token authentication (`Authorization: Bearer ss_xxxxx`). This works for:
- Claude Code (supports HTTP transport with static headers)
- Claude Desktop via `mcp-remote` proxy (workaround)

To work **natively** in Claude Desktop as a Custom Connector (via Settings > Connectors), we need to implement OAuth 2.0/2.1 authentication.

## Claude Desktop Requirements

### Availability
- Pro, Max, Team, and Enterprise plan users
- Configuration via **Settings > Connectors** (not `claude_desktop_config.json`)

### OAuth Callback URLs (must allowlist both)
```
https://claude.ai/api/mcp/auth_callback
https://claude.com/api/mcp/auth_callback
```

### OAuth Client Name
```
Claude
```

### Supported Specifications
- MCP 3/26 auth specification
- MCP 6/18 auth specification

### Supported Features
- Tools (text and image-based results) ✅ We have this
- Prompts ✅ We have this
- Resources (text and binary-based) ✅ We have this

### Not Yet Supported by Claude
- Resource subscriptions
- Sampling
- Advanced draft capabilities

## Implementation Plan

### Option A: Doorkeeper Gem (Recommended)

[Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper) is the standard OAuth 2 provider gem for Rails.

#### Installation

```ruby
# Gemfile
gem 'doorkeeper'
```

```bash
bundle install
rails generate doorkeeper:install
rails generate doorkeeper:migration
rails db:migrate
```

#### Required Endpoints (provided by Doorkeeper)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/oauth/authorize` | GET | Authorization screen |
| `/oauth/token` | POST | Token exchange |
| `/oauth/token/info` | GET | Token introspection |
| `/oauth/revoke` | POST | Token revocation |
| `/oauth/applications` | GET | Manage OAuth apps (admin) |

#### Database Tables (created by migration)

1. **oauth_applications** - OAuth client credentials
   - `uid` (client_id)
   - `secret` (client_secret)
   - `name`
   - `redirect_uri`
   - `scopes`
   - `confidential`

2. **oauth_access_grants** - Authorization codes
   - `resource_owner_id` (user_id)
   - `application_id`
   - `token` (authorization code)
   - `expires_in`
   - `redirect_uri`
   - `scopes`

3. **oauth_access_tokens** - Access/refresh tokens
   - `resource_owner_id` (user_id)
   - `application_id`
   - `token` (access_token)
   - `refresh_token`
   - `expires_in`
   - `scopes`

#### Configuration

```ruby
# config/initializers/doorkeeper.rb
Doorkeeper.configure do
  # Our custom User model (not Devise)
  resource_owner_authenticator do
    User.find_by(id: session[:user_id]) || redirect_to(login_path)
  end

  # Or use our existing authentication
  resource_owner_from_credentials do |routes|
    user = User.find_by(email: params[:username])
    user if user&.authenticate(params[:password])
  end

  # Token expiration
  access_token_expires_in 2.hours

  # Enable refresh tokens
  use_refresh_token

  # Scopes
  default_scopes :read
  optional_scopes :write, :admin

  # Grant flows
  grant_flows %w[authorization_code client_credentials]

  # For Claude Desktop - allow confidential clients
  allow_blank_redirect_uri false

  # PKCE support (recommended for public clients)
  force_ssl_in_redirect_uri false # Set true in production
end
```

### Option B: Dynamic Client Registration (DCR)

Claude supports DCR for automatic client credential management. This means Claude can register itself as an OAuth client automatically.

#### Additional Endpoint Required

```
POST /oauth/register
```

#### DCR Request Format
```json
{
  "client_name": "Claude",
  "redirect_uris": [
    "https://claude.ai/api/mcp/auth_callback",
    "https://claude.com/api/mcp/auth_callback"
  ],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "client_secret_basic"
}
```

#### DCR Response Format
```json
{
  "client_id": "generated_client_id",
  "client_secret": "generated_client_secret",
  "client_name": "Claude",
  "redirect_uris": [...],
  "grant_types": [...],
  "registration_access_token": "token_for_updates",
  "registration_client_uri": "https://your-server.com/oauth/register/client_id"
}
```

### Integration with MCP Authentication

#### Current Flow (Bearer Token)
```
Claude Code → Authorization: Bearer ss_xxxxx → MCP Controller → Validate ApiKey → Process
```

#### New Flow (OAuth)
```
Claude Desktop → Authorization: Bearer <oauth_access_token> → MCP Controller → Validate OAuth Token → Get User → Process
```

#### Updated MCP Authentication Concern

```ruby
# app/controllers/concerns/mcp_authentication.rb
module McpAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_mcp_request
  end

  private

  def authenticate_mcp_request
    if bearer_token.present?
      # Try OAuth token first
      if (oauth_token = Doorkeeper::AccessToken.find_by(token: bearer_token))
        if oauth_token.accessible?
          @current_user = User.find(oauth_token.resource_owner_id)
          return
        end
      end

      # Fall back to API key
      if (api_key = ApiKey.find_by(key: bearer_token))
        @current_user = api_key.user
        return
      end
    end

    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def bearer_token
    request.headers['Authorization']&.gsub(/^Bearer /, '')
  end
end
```

## OAuth Flow Diagram

```
┌──────────────┐                                    ┌──────────────────┐
│Claude Desktop│                                    │ SmartSuite MCP   │
│  (Connector) │                                    │     Server       │
└──────┬───────┘                                    └────────┬─────────┘
       │                                                      │
       │  1. User adds connector URL                         │
       │─────────────────────────────────────────────────────▶│
       │                                                      │
       │  2. Server returns OAuth metadata                    │
       │◀─────────────────────────────────────────────────────│
       │     (authorization_endpoint, token_endpoint)         │
       │                                                      │
       │  3. Claude opens browser to /oauth/authorize         │
       │─────────────────────────────────────────────────────▶│
       │                                                      │
       │  4. User logs in (our login page)                   │
       │◀ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
       │                                                      │
       │  5. User authorizes access                          │
       │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─▶│
       │                                                      │
       │  6. Redirect to callback with auth code             │
       │◀─────────────────────────────────────────────────────│
       │     (claude.ai/api/mcp/auth_callback?code=xxx)       │
       │                                                      │
       │  7. Claude exchanges code for tokens                 │
       │─────────────────────────────────────────────────────▶│
       │     POST /oauth/token                                │
       │                                                      │
       │  8. Server returns access_token + refresh_token      │
       │◀─────────────────────────────────────────────────────│
       │                                                      │
       │  9. Claude uses access_token for MCP requests        │
       │─────────────────────────────────────────────────────▶│
       │     Authorization: Bearer <access_token>             │
       │                                                      │
       │  10. Server validates token and processes request    │
       │◀─────────────────────────────────────────────────────│
       │                                                      │
```

## OAuth Server Metadata Endpoint

Claude expects a well-known endpoint for OAuth discovery:

```
GET /.well-known/oauth-authorization-server
```

Response:
```json
{
  "issuer": "https://18.218.237.50.nip.io",
  "authorization_endpoint": "https://18.218.237.50.nip.io/oauth/authorize",
  "token_endpoint": "https://18.218.237.50.nip.io/oauth/token",
  "registration_endpoint": "https://18.218.237.50.nip.io/oauth/register",
  "scopes_supported": ["read", "write"],
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post"],
  "code_challenge_methods_supported": ["S256"]
}
```

## Implementation Checklist

### Phase 1: Basic OAuth Setup
- [x] Add `doorkeeper` gem
- [x] Run Doorkeeper migrations
- [x] Configure Doorkeeper initializer
- [x] Create login/authorization views
- [x] Add OAuth metadata endpoint (`.well-known/oauth-authorization-server`)

### Phase 2: Integration
- [x] Update MCP authentication to support OAuth tokens
- [x] Add OAuth token validation to `McpAuthentication` concern
- [ ] Test with MCP Inspector tool

### Phase 3: DCR Support (Optional)
- [x] Implement `/oauth/register` endpoint
- [x] Handle DCR client registration from Claude
- [ ] Handle `invalid_client` error for client deletion signal

### Phase 4: User Experience
- [x] Create nice authorization screen (branded)
- [ ] Add scope descriptions
- [x] Handle token refresh gracefully
- [ ] Add admin UI for managing OAuth applications

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Basic OAuth | 4-6 hours |
| Phase 2: Integration | 2-3 hours |
| Phase 3: DCR Support | 2-4 hours |
| Phase 4: UX Polish | 2-4 hours |
| **Total** | **10-17 hours (~2 days)** |

## Testing

### MCP Inspector
Use the [MCP Inspector](https://github.com/anthropics/mcp-inspector) tool to validate:
- OAuth flow works correctly
- Token exchange succeeds
- MCP tools are accessible after authentication

### Manual Testing
1. Add server URL in Claude Desktop > Settings > Connectors
2. Complete OAuth flow
3. Verify MCP tools appear
4. Test: "List my SmartSuite solutions"

## References

- [Claude Custom Connectors Documentation](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers)
- [Doorkeeper Gem](https://github.com/doorkeeper-gem/doorkeeper)
- [Doorkeeper Guides](https://doorkeeper.gitbook.io/guides)
- [MCP OAuth Specification](https://spec.modelcontextprotocol.io/specification/authentication/)
- [RFC 6749 - OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)

## Current Status

**Implemented** - Core OAuth functionality is complete as of December 2024.

Remaining items:
- Test with MCP Inspector tool
- Handle `invalid_client` error for client deletion signal
- Add scope descriptions in UI
- Add admin UI for managing OAuth applications

Current workaround for users without password: Use `mcp-remote` proxy with API key authentication.
