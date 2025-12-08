# SmartSuite MCP Server

A Model Context Protocol (MCP) server for SmartSuite that enables AI assistants like Claude to interact with your SmartSuite workspace through natural language.

[![Version](https://img.shields.io/badge/version-2.0.0-blue)]()
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)]()
[![Coverage](https://img.shields.io/badge/coverage-92.78%25-brightgreen)]()
[![Ruby](https://img.shields.io/badge/ruby-3.4.7-red)]()
[![Rails](https://img.shields.io/badge/rails-8.1.1-red)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

## ✨ Features

- **Comprehensive SmartSuite API Coverage** - Solutions, tables, records (including bulk operations), fields, members, comments, views, and deleted records management
- **Aggressive SQLite Caching** - 12-hour TTL with cache-first strategy (75%+ API call reduction)
- **Token Optimization** - TOON format responses and filtered structures (60%+ token savings)
- **Session Tracking** - Monitor API usage by user, solution, table, and endpoint
- **Smart Filtering** - Local SQL queries on cached data with SmartSuite filter syntax support
- **Dual Mode Operation** - Run as stdio MCP server or hosted Rails API server

## 🚀 Quick Start

### Option 1: Stdio MCP Server (Claude Desktop)

The traditional MCP server mode communicates via stdin/stdout with Claude Desktop.

#### One-Liner Installation (Easiest!)

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Grupo-AFAL/smartsuite_mcp_server/main/bootstrap.sh | bash

# Windows (PowerShell)
irm https://raw.githubusercontent.com/Grupo-AFAL/smartsuite_mcp_server/main/bootstrap.ps1 | iex
```

**That's it!** The script will:
- ✅ Check for Git (required) and provide install instructions if needed
- ✅ Clone the repository to `~/.smartsuite_mcp`
- ✅ Auto-install Homebrew on macOS (if needed)
- ✅ Auto-install Ruby via package manager (if needed)
- ✅ Install all dependencies
- ✅ Prompt for your SmartSuite API credentials
- ✅ Configure Claude Desktop automatically

Just restart Claude Desktop when done!

#### Alternative: Manual Clone + Script

```bash
# Clone the repository
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git
cd smartsuite_mcp_server

# Run the installation script
./install.sh          # macOS/Linux
.\install.ps1         # Windows
```

### Option 2: Hosted Rails Server (Multi-User API)

The hosted mode runs as a Rails API server with PostgreSQL, supporting multiple users and API key authentication.

#### Prerequisites

- Ruby 3.4.7+
- PostgreSQL
- Redis (optional, for caching)

#### Setup

```bash
# Clone and install
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git
cd smartsuite_mcp_server
bundle install

# Setup database
bin/rails db:create db:migrate

# Start server
bin/rails server
```

#### Environment Variables

```bash
# Required for hosted mode
DATABASE_URL=postgres://user:pass@localhost/smartsuite_mcp
RAILS_MASTER_KEY=your_master_key

# SmartSuite credentials (can be per-user via API)
SMARTSUITE_API_KEY=your_api_key
SMARTSUITE_ACCOUNT_ID=your_account_id
```

#### Deployment with Kamal

The server includes Kamal configuration for easy deployment:

```bash
# Copy example config
cp config/deploy.yml.example config/deploy.yml

# Edit with your settings
# - DEPLOY_SERVER_IP
# - DEPLOY_HOST
# - KAMAL_REGISTRY_USERNAME

# Deploy
kamal setup
kamal deploy
```

See [Deployment Guide](docs/deployment/kamal.md) for detailed instructions.

### Get API Credentials

Before installation, get your SmartSuite credentials:

1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Go to Settings → API
3. Generate an API key and note your Account ID

## 📚 Documentation

### Getting Started
- [Installation Guide](docs/getting-started/installation.md) - Detailed setup instructions
- [Quick Start Tutorial](docs/getting-started/quick-start.md) - 5-minute walkthrough
- [Configuration Options](docs/getting-started/configuration.md) - All environment variables and settings
- [Troubleshooting](docs/getting-started/troubleshooting.md) - Common issues and solutions

### Guides
- [User Guide](docs/guides/user-guide.md) - How to use the server with Claude
- [Caching Guide](docs/guides/caching-guide.md) - Understanding the cache system
- [Filtering Guide](docs/guides/filtering-guide.md) - Filter syntax and examples
- [Performance Guide](docs/guides/performance-guide.md) - Optimization tips

### API Reference
- [Workspace Operations](docs/api/workspace.md) - Solutions and usage analysis
- [Table Operations](docs/api/tables.md) - Tables and schemas
- [Record Operations](docs/api/records.md) - CRUD operations, bulk operations, file URLs, deleted records
- [Field Operations](docs/api/fields.md) - Schema management
- [Member Operations](docs/api/members.md) - Users and teams
- [Complete API Documentation](docs/api/)

### Architecture
- [Overview](docs/architecture/overview.md) - High-level architecture
- [Caching System](docs/architecture/caching-system.md) - How caching works
- [MCP Protocol](docs/architecture/mcp-protocol.md) - MCP implementation details
- [Design Decisions](docs/architecture/design-decisions.md) - Why we made certain choices

## 💡 Examples

```ruby
# List all solutions with usage metrics
list_solutions(include_activity_data: true)

# Get records with caching (uses local SQLite cache)
list_records('table_abc123', 10, 0, fields: ['status', 'priority'])

# Create a record
create_record('table_abc123', {
  'status' => 'Active',
  'priority' => 'High',
  'assigned_to' => ['user_xyz789']
})

# Refresh cache when needed
refresh_cache('records', table_id: 'table_abc123')
```

See [examples/](docs/examples/) for more usage patterns.

## 🧪 Testing

```bash
# Run all unit tests
bundle exec rake test

# Run integration tests (requires API credentials)
bundle exec rake test:integration

# Run with verbose output
bundle exec rake test TESTOPTS="-v"
```

## 🛠️ Utility Scripts

The server includes CLI utility scripts for administrative and batch operations:

### Batch Markdown Converter

Convert multiple SmartSuite records from Markdown to SmartDoc format in bulk:

```bash
# Convert all webhook-generated records
bin/convert_markdown_sessions

# Dry-run to preview changes
bin/convert_markdown_sessions --dry-run --limit 10
```

**Use Cases:**
- Automated webhook data (Read.ai meeting transcripts, etc.)
- Bulk data formatting/migration
- Scheduled transformation tasks

**Documentation:** [Batch Markdown Conversion Guide](docs/guides/markdown-batch-conversion.md)

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- [Code Style](docs/contributing/code-style.md)
- [Testing Guidelines](docs/contributing/testing.md)
- [Documentation Standards](docs/contributing/documentation.md)

## 📋 Project Status

- **Current Version:** 2.0.0
- **Ruby:** 3.4.7
- **Rails:** 8.1.1 (hosted mode)
- **Roadmap:** See [ROADMAP.md](ROADMAP.md)
- **Changelog:** See [CHANGELOG.md](CHANGELOG.md)

## 🐛 Support

- **Issues:** [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
- **Troubleshooting:** See [docs/getting-started/troubleshooting.md](docs/getting-started/troubleshooting.md)

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

Built with the [Model Context Protocol](https://modelcontextprotocol.io/) by Anthropic.

---

**⚡ Performance Stats**
- Cache hit rate: >80% for metadata queries
- API call reduction: >75% vs uncached
- Token savings: >60% average per session
- Response time: <100ms for cached queries
