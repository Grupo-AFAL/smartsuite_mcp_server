# Quick Start Guide

Get up and running with SmartSuite MCP Server in 5 minutes.

## Prerequisites

- Ruby 3.0+ installed
- Claude Desktop installed
- SmartSuite account with API access

## Step 1: Get SmartSuite Credentials

1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Click your profile → **Settings**
3. Navigate to **API** section
4. Click **Generate API Key**
5. Copy your **API Key** and **Account ID**

## Step 2: Install the Server

```bash
# Clone the repository
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git
cd smartsuite_mcp_server

# Install dependencies
bundle install

# Make server executable
chmod +x smartsuite_server.rb
```

## Step 3: Configure Claude Desktop

Edit Claude Desktop config file:

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

Add this configuration:

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/absolute/path/to/smartsuite_mcp_server/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "your_api_key_here",
        "SMARTSUITE_ACCOUNT_ID": "your_account_id_here"
      }
    }
  }
}
```

**Important:** Replace `/absolute/path/to` with the actual path on your system.

## Step 4: Restart Claude Desktop

1. Quit Claude Desktop completely
2. Relaunch Claude Desktop
3. Look for the 🔌 icon indicating MCP servers are connected

## Step 5: Try It Out!

Ask Claude to interact with SmartSuite:

### Example 1: List Your Solutions

```
Show me all my SmartSuite solutions
```

Claude will use the `list_solutions` tool to fetch your workspaces.

### Example 2: Get Records from a Table

First, get the table ID:

```
What tables are in my "Projects" solution?
```

Then fetch records:

```
Show me the first 10 records from table tbl_abc123,
including the status and priority fields
```

### Example 3: Create a Record

```
Create a new record in table tbl_abc123 with:
- Status: Active
- Priority: High
- Name: New Project
```

## Understanding the Response

The server returns data in plain text format to save tokens:

```
=== RECORDS (3 of 25 total) ===

--- Record 1 of 3 ---
id: rec_123abc
status: Active
priority: High
name: Project Alpha

--- Record 2 of 3 ---
id: rec_456def
status: Pending
priority: Medium
name: Project Beta

[... and so on]
```

## Cache Behavior

By default, the server caches data for 4 hours:

- **First request:** Fetches from SmartSuite API (slow)
- **Subsequent requests:** Reads from local SQLite cache (fast)
- **Expired cache:** Automatically refreshes when TTL expires

To force fresh data:

```
Show me the latest records from table tbl_abc123 (bypass cache)
```

## Next Steps

- **[User Guide](../guides/user-guide.md)** - Learn more about using the server
- **[Caching Guide](../guides/caching-guide.md)** - Understand caching behavior
- **[Filtering Guide](../guides/filtering-guide.md)** - Master advanced filters
- **[API Reference](../api/)** - Explore all available operations

## Troubleshooting

**Server not showing up?**
- Check Claude Desktop logs: `~/Library/Logs/Claude/mcp*.log`
- Verify the path in config is absolute and correct
- Ensure Ruby 3.0+ is in your PATH

**Getting errors?**
- Verify your API credentials are correct
- Check you have permissions in SmartSuite
- See [Troubleshooting Guide](troubleshooting.md)

## Need Help?

- [Troubleshooting Guide](troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
