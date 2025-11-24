# Configuration Guide

Advanced configuration options for SmartSuite MCP Server.

## Overview

The SmartSuite MCP Server is configured through environment variables passed via your Claude Desktop configuration file. This guide covers all available configuration options and advanced settings.

---

## Required Configuration

### Environment Variables

Two environment variables are **required** for the server to function:

#### `SMARTSUITE_API_KEY`

Your SmartSuite API authentication key.

**How to get it:**
1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Go to Settings → API
3. Click "Generate API Key"
4. Copy the generated key

**Example:**
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "sk_live_abc123def456..."
  }
}
```

**Security Notes:**
- Never commit API keys to version control
- Keep keys secure and private
- Regenerate if compromised

#### `SMARTSUITE_ACCOUNT_ID`

Your SmartSuite workspace account identifier.

**How to get it:**
1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Go to Settings → API
3. Find your Account ID (shown above API key section)

**Example:**
```json
{
  "env": {
    "SMARTSUITE_ACCOUNT_ID": "acc_xyz789..."
  }
}
```

---

## Optional Configuration

### Timezone Configuration

The server automatically converts UTC timestamps from SmartSuite to your local timezone. Configure your timezone for accurate date display.

#### `SMARTSUITE_USER_EMAIL` (Recommended)

Your SmartSuite email address for automatic timezone detection from your user profile.

**Example:**
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "...",
    "SMARTSUITE_ACCOUNT_ID": "...",
    "SMARTSUITE_USER_EMAIL": "user@example.com"
  }
}
```

**How it works:**
1. On startup, the server searches for your user by email
2. Retrieves your timezone setting from your SmartSuite profile
3. Automatically configures date formatting to match what you see in SmartSuite UI

**Why use this?** The SmartSuite API doesn't provide a way to identify the API key owner, so without this setting, the server uses the first member's timezone found in your workspace (which may not be yours).

#### `SMARTSUITE_TIMEZONE` (Manual Override)

Directly specify your timezone if you prefer not to use automatic detection.

**Supported formats:**
- Named timezones: `America/Mexico_City`, `Europe/London`, `Asia/Tokyo`
- UTC offsets: `+0530`, `-0800`, `+0000`
- Special values: `utc` (no conversion)

**Example:**
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "...",
    "SMARTSUITE_ACCOUNT_ID": "...",
    "SMARTSUITE_TIMEZONE": "America/Mexico_City"
  }
}
```

**Named timezone advantages:**
- Automatically handles Daylight Saving Time (DST) transitions
- July dates use summer offset (e.g., -0700 PDT)
- January dates use winter offset (e.g., -0800 PST)

**Priority order:**
1. `SMARTSUITE_TIMEZONE` (if set, takes precedence)
2. `SMARTSUITE_USER_EMAIL` (automatic detection from profile)
3. System timezone (fallback)

### Cache Configuration

#### `CACHE_PATH`

Customize the location of the SQLite cache database.

**Default:** `~/.smartsuite_mcp_cache.db`

**Example:**
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "...",
    "SMARTSUITE_ACCOUNT_ID": "...",
    "CACHE_PATH": "/custom/path/to/cache.db"
  }
}
```

**Use cases:**
- Store cache on a different drive
- Use project-specific cache files
- Network-mounted storage
- Custom backup locations

**Important:**
- Path must be writable by the server process
- Directory must exist before server starts
- File will be created automatically if it doesn't exist

---

## Complete Configuration Example

### macOS

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/Users/yourname/projects/smartsuite_mcp_server/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_abc123def456...",
        "SMARTSUITE_ACCOUNT_ID": "acc_xyz789...",
        "SMARTSUITE_USER_EMAIL": "yourname@company.com"
      }
    }
  }
}
```

### Windows

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["C:\\Users\\YourName\\Projects\\smartsuite_mcp_server\\smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_abc123def456...",
        "SMARTSUITE_ACCOUNT_ID": "acc_xyz789...",
        "SMARTSUITE_USER_EMAIL": "yourname@company.com"
      }
    }
  }
}
```

### Linux

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/home/yourname/projects/smartsuite_mcp_server/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_abc123def456...",
        "SMARTSUITE_ACCOUNT_ID": "acc_xyz789...",
        "SMARTSUITE_USER_EMAIL": "yourname@company.com"
      }
    }
  }
}
```

---

## Cache Behavior

### Default Settings

- **Cache TTL:** 4 hours (per table)
- **Cache Strategy:** Cache-first (queries hit cache before API)
- **Cache Location:** `~/.smartsuite_mcp_cache.db`
- **Invalidation:** TTL-based (not mutation-based)

### How It Works

1. **First query:** Cache miss → Fetch all records → Store in cache
2. **Subsequent queries:** Cache hit → Query local SQLite
3. **After 4 hours:** Cache expires → Next query refetches data
4. **On mutations:** Cache not invalidated (use `bypass_cache: true` for fresh data)

### Bypass Cache

To force fresh data from the API:

```ruby
list_records('table_id', 10, 0,
  fields: ['status'],
  bypass_cache: true
)
```

**When to bypass:**
- After creating/updating/deleting records
- When you need guaranteed fresh data
- Testing or debugging
- Real-time monitoring scenarios

---

## Environment Variable Alternatives

### Using .env File

Some users prefer storing credentials in a `.env` file (not recommended for MCP servers):

**Create `.env` in project root:**
```bash
SMARTSUITE_API_KEY=sk_live_abc123...
SMARTSUITE_ACCOUNT_ID=acc_xyz789...
```

**Reference in config:**
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "${SMARTSUITE_API_KEY}",
    "SMARTSUITE_ACCOUNT_ID": "${SMARTSUITE_ACCOUNT_ID}"
  }
}
```

**Note:** Environment variable substitution support varies by MCP client. Claude Desktop may not support this.

### System Environment Variables

You can also set environment variables at the system level:

**macOS/Linux:**
```bash
# Add to ~/.zshrc or ~/.bashrc
export SMARTSUITE_API_KEY="sk_live_abc123..."
export SMARTSUITE_ACCOUNT_ID="acc_xyz789..."
```

**Windows (PowerShell):**
```powershell
[System.Environment]::SetEnvironmentVariable('SMARTSUITE_API_KEY', 'sk_live_abc123...', 'User')
[System.Environment]::SetEnvironmentVariable('SMARTSUITE_ACCOUNT_ID', 'acc_xyz789...', 'User')
```

Then reference in Claude config (may not work in all MCP clients):
```json
{
  "env": {
    "SMARTSUITE_API_KEY": "${SMARTSUITE_API_KEY}",
    "SMARTSUITE_ACCOUNT_ID": "${SMARTSUITE_ACCOUNT_ID}"
  }
}
```

**Recommended:** Directly specify values in `claude_desktop_config.json` for best compatibility.

---

## Multiple Workspace Configuration

You can configure multiple SmartSuite workspaces by creating separate server entries:

```json
{
  "mcpServers": {
    "smartsuite-production": {
      "command": "ruby",
      "args": ["/path/to/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_prod_...",
        "SMARTSUITE_ACCOUNT_ID": "acc_prod_...",
        "CACHE_PATH": "~/.smartsuite_cache_prod.db"
      }
    },
    "smartsuite-staging": {
      "command": "ruby",
      "args": ["/path/to/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_staging_...",
        "SMARTSUITE_ACCOUNT_ID": "acc_staging_...",
        "CACHE_PATH": "~/.smartsuite_cache_staging.db"
      }
    }
  }
}
```

**Benefits:**
- Separate production and test environments
- Different caches for each workspace
- Easy workspace switching in Claude

---

## Configuration Validation

### Test Your Configuration

After configuring, verify it works:

1. **Restart Claude Desktop** (Cmd+Q, then relaunch)
2. **Check server appears** (🔌 icon in bottom right)
3. **Test query:**
   ```
   List my SmartSuite solutions
   ```

### Troubleshooting Configuration

**Server not appearing?**

Check Claude Desktop logs:

**macOS:**
```bash
tail -f ~/Library/Logs/Claude/mcp*.log
```

**Windows:**
```powershell
Get-Content "$env:APPDATA\Claude\logs\mcp*.log" -Wait
```

**Common issues:**
- ❌ Relative path used → Use absolute path
- ❌ Syntax error in JSON → Validate JSON
- ❌ Wrong API credentials → Check Settings → API
- ❌ Missing quotes → Ensure all strings are quoted

**API errors?**

Test credentials manually:
```bash
curl -H "Authorization: Token YOUR_API_KEY" \
     -H "Account-Id: YOUR_ACCOUNT_ID" \
     https://app.smartsuite.com/api/v1/solutions/
```

Should return JSON (not 401 Unauthorized).

---

## Cache Management

### View Cache Status

Ask Claude:
```
Show me the cache status
```

This displays:
- Cached tables and record counts
- Cache expiration times
- Time remaining until expiry

### Clear Cache

The cache is automatically managed, but you can manually clear it:

```bash
# Remove cache file
rm ~/.smartsuite_mcp_cache.db

# Or remove custom location
rm /custom/path/to/cache.db
```

The cache will rebuild automatically on the next query.

### Cache Performance

Monitor cache performance:
```
Show me API statistics
```

Displays:
- Cache hit rate (>80% is good)
- API call reduction percentage
- Requests by endpoint
- Session tracking data

---

## Next Steps

- **[Installation Guide](installation.md)** - Basic setup
- **[User Guide](../guides/user-guide.md)** - How to use the server
- **[Caching Guide](../guides/caching-guide.md)** - Deep dive into caching
- **[Troubleshooting](troubleshooting.md)** - Common issues

## Need Help?

- [Troubleshooting Guide](troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
