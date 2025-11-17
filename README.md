# SmartSuite MCP Server

A Model Context Protocol (MCP) server for SmartSuite that enables AI assistants like Claude to interact with your SmartSuite workspace through natural language.

[![Tests](https://img.shields.io/badge/tests-passing-brightgreen)]()
[![Ruby](https://img.shields.io/badge/ruby-3.0+-red)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

## ✨ Features

- **Full SmartSuite API Coverage** - Solutions, tables, records, fields, members, comments, and views
- **Aggressive SQLite Caching** - 4-hour TTL with cache-first strategy (75%+ API call reduction)
- **Token Optimization** - Plain text responses and filtered structures (60%+ token savings)
- **Session Tracking** - Monitor API usage by user, solution, table, and endpoint
- **Smart Filtering** - Local SQL queries on cached data with SmartSuite filter syntax support

## 🚀 Quick Start

### One-Liner Installation (Easiest!)

Install the SmartSuite MCP server with just one command:

#### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Grupo-AFAL/smartsuite_mcp_server/main/bootstrap.sh | bash
```

#### Windows (PowerShell)

```powershell
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

### Alternative: Manual Clone + Script

If you prefer to clone the repository yourself first:

```bash
# Clone the repository
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git
cd smartsuite_mcp_server

# Run the installation script
./install.sh          # macOS/Linux
.\install.ps1         # Windows
```

### Get API Credentials

Before running the install script, get your SmartSuite credentials:

1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Go to Settings → API
3. Generate an API key and note your Account ID

### Manual Installation (Alternative)

If you prefer to install manually or the automated script doesn't work for your setup:

```bash
# Clone the repository
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git
cd smartsuite_mcp_server

# Install dependencies
bundle install

# Make server executable
chmod +x smartsuite_server.rb
```

Then manually add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/path/to/smartsuite_mcp_server/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "your_api_key",
        "SMARTSUITE_ACCOUNT_ID": "your_account_id"
      }
    }
  }
}
```

**Note:** Replace `/path/to/smartsuite_mcp_server/` with the actual path where you cloned the repository.

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
- [Record Operations](docs/api/records.md) - CRUD operations
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

# Bypass cache for fresh data
list_records('table_abc123', 10, 0,
  fields: ['status'],
  bypass_cache: true
)
```

See [examples/](examples/) for more usage patterns.

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- [Code Style](docs/contributing/code-style.md)
- [Testing Guidelines](docs/contributing/testing.md)
- [Documentation Standards](docs/contributing/documentation.md)

## 📋 Project Status

- **Current Version:** 1.5.0
- **Development:** v1.6 in progress (15% complete)
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
