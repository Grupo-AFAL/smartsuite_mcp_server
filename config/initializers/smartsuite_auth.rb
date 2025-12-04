# frozen_string_literal: true

# SmartSuite MCP Server Authentication Configuration
#
# AUTH_MODE determines how users authenticate to the MCP server:
#
# - "remote" (default for production): Users authenticate via API keys stored
#   in the database. Each user has their own SmartSuite credentials.
#   Requires: PostgreSQL database with users and api_keys tables
#
# - "local": Single user mode using environment variables for SmartSuite
#   credentials. No database authentication required.
#   Requires: SMARTSUITE_API_KEY and SMARTSUITE_ACCOUNT_ID env vars
#
# Set via environment variable:
#   AUTH_MODE=local  (for local standalone server)
#   AUTH_MODE=remote (for hosted multi-user server)

Rails.application.config.smartsuite_auth_mode = ENV.fetch("AUTH_MODE", "remote").to_sym
