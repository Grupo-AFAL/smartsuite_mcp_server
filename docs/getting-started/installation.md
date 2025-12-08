# Installation Guide

Complete installation instructions for SmartSuite MCP Server.

## Quick Install (Recommended)

The easiest way to get started is using our automated installation scripts.

### Option A: Connect to Hosted Server (Remote Mode)

If you have access to a hosted SmartSuite MCP server, use this mode:

**macOS/Linux:**

```bash
curl -fsSL 'https://your-server.com/install.sh' | bash -s -- remote 'https://your-server.com/mcp' 'YOUR_API_KEY'
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy Bypass -c "iwr -useb 'https://your-server.com/install.ps1' -OutFile install.ps1; .\install.ps1 remote 'https://your-server.com/mcp' 'YOUR_API_KEY'"
```

### Option B: Run Server Locally (Local Mode)

For full control or offline capability, run the server on your machine:

**macOS/Linux:**

```bash
curl -fsSL 'https://your-server.com/install.sh' | bash -s -- local
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy Bypass -c "iwr -useb 'https://your-server.com/install.ps1' -OutFile install.ps1; .\install.ps1 local"
```

The installer will:
1. Check for and install Node.js (remote) or Ruby (local) if needed
2. Download and configure the MCP server
3. Generate Claude Desktop configuration
4. Optionally create the config file for you

### Web-Based Install Page

If your server provides a web interface, visit `/install` for a guided setup experience with OS detection and copy-paste commands.

### Local vs Remote Mode Comparison

| Feature | Local Mode | Remote Mode |
|---------|------------|-------------|
| **Requirements** | Ruby 3.0+ | Node.js (npx) |
| **SmartSuite credentials** | Your own API key | Server API key |
| **Cache location** | Local SQLite | Server PostgreSQL |
| **Offline support** | Yes (cached data) | No |
| **Best for** | Single user, full control | Teams, managed setup |
| **Setup complexity** | Medium | Easy |

---

## Manual Installation

If you prefer manual installation or the scripts don't work for your environment, follow these steps.

## Prerequisites

### System Requirements

- **Ruby:** 3.0 or higher
- **Operating System:** macOS, Linux, or Windows
- **Claude Desktop:** Latest version
- **Git:** For cloning the repository

### SmartSuite Requirements

- Active SmartSuite account
- API access enabled
- API key and Account ID

## Installation Steps

### 1. Install Ruby

#### macOS (using Homebrew)

```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Ruby
brew install ruby

# Verify installation
ruby --version  # Should be 3.0+
```

#### macOS (using rbenv - recommended)

```bash
# Install rbenv
brew install rbenv

# Install Ruby 3.4.7
rbenv install 3.4.7
rbenv global 3.4.7

# Verify installation
ruby --version
```

#### Linux (Ubuntu/Debian)

```bash
# Install Ruby
sudo apt-get update
sudo apt-get install ruby-full

# Verify installation
ruby --version
```

#### Windows

1. Download Ruby installer from [RubyInstaller](https://rubyinstaller.org/)
2. Run installer (select "Add Ruby to PATH")
3. Verify: `ruby --version`

### 2. Clone the Repository

```bash
# Clone from GitHub
git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git

# Navigate to directory
cd smartsuite_mcp_server
```

### 3. Install Dependencies

```bash
# Install bundler if needed
gem install bundler

# Install project dependencies
bundle install
```

This installs only Ruby standard library dependencies (no external gems required).

### 4. Make Server Executable

```bash
chmod +x smartsuite_server.rb
```

### 5. Get SmartSuite API Credentials

#### Step-by-step:

1. Log in to [SmartSuite](https://app.smartsuite.com)
2. Click your profile icon (top right)
3. Select **Settings**
4. Navigate to **API** tab
5. Click **Generate API Key**
6. Copy the generated **API Key**
7. Copy your **Account ID** (shown above the API key section)

**Important:** Keep your API key secure! Never commit it to version control.

### 6. Configure Claude Desktop

#### Locate Config File

**macOS:**

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

**Windows:**

```
%APPDATA%\Claude\claude_desktop_config.json
```

**Linux:**

```
~/.config/Claude/claude_desktop_config.json
```

#### Edit Configuration

Add the SmartSuite server to your config:

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

**Critical:**

- Use the **absolute path** to `smartsuite_server.rb`
- Replace `your_api_key_here` with your actual API key
- Replace `your_account_id_here` with your actual Account ID

#### Example (macOS):

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": [
        "/Users/yourname/projects/smartsuite_mcp_server/smartsuite_server.rb"
      ],
      "env": {
        "SMARTSUITE_API_KEY": "sk_live_abc123...",
        "SMARTSUITE_ACCOUNT_ID": "acc_xyz789..."
      }
    }
  }
}
```

### 7. Restart Claude Desktop

1. **Quit Claude Desktop** completely (Cmd+Q on macOS)
2. **Relaunch Claude Desktop**
3. Look for the **🔌 icon** in the bottom right
4. Server should appear as "smartsuite"

## Verification

### Test the Connection

Ask Claude:

```
What SmartSuite tools are available?
```

Claude should list all SmartSuite MCP tools (list_solutions, list_records, etc.).

### Test a Real Query

```
List my SmartSuite solutions
```

If successful, you'll see your SmartSuite workspaces!

## Troubleshooting

### Server Not Appearing?

**Check Claude Desktop Logs:**

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
- ❌ Wrong Ruby version → Must be 3.0+
- ❌ Missing `bundle install` → Run it
- ❌ Syntax error in JSON config → Validate JSON

### Connection Errors?

**Check API Credentials:**

```bash
# Test API key manually
curl -H "Authorization: Token YOUR_API_KEY" \
     -H "Account-Id: YOUR_ACCOUNT_ID" \
     https://app.smartsuite.com/api/v1/solutions/
```

Should return JSON (not 401 Unauthorized).

**Common issues:**

- ❌ Wrong API key → Regenerate in SmartSuite
- ❌ Wrong Account ID → Check Settings > API
- ❌ API access disabled → Contact SmartSuite support

### Ruby Version Issues?

```bash
# Check Ruby version
ruby --version

# If < 3.0, install newer version
rbenv install 3.4.7
rbenv global 3.4.7
```

## Optional Configuration

### Using .env File (Alternative)

Create `.env` file in project root:

```bash
SMARTSUITE_API_KEY=your_api_key_here
SMARTSUITE_ACCOUNT_ID=your_account_id_here
```

Then reference in Claude config:

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/path/to/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "${SMARTSUITE_API_KEY}",
        "SMARTSUITE_ACCOUNT_ID": "${SMARTSUITE_ACCOUNT_ID}"
      }
    }
  }
}
```

**Note:** Environment variable substitution support varies by MCP client.

### Cache Location

Default cache location:

```
~/.smartsuite_mcp_cache.db
```

To use custom location, set `CACHE_PATH` in env:

```json
"env": {
  "SMARTSUITE_API_KEY": "...",
  "SMARTSUITE_ACCOUNT_ID": "...",
  "CACHE_PATH": "/custom/path/cache.db"
}
```

## Updating

### Pull Latest Changes

```bash
cd smartsuite_mcp_server
git pull origin main
bundle install
```

### Check for Breaking Changes

See [CHANGELOG.md](../../CHANGELOG.md) for version changes.

### Restart Claude Desktop

After updating, restart Claude Desktop to load new version.

## Uninstallation

### Remove Server

```bash
# Remove from Claude Desktop config
# Delete the "smartsuite" entry from claude_desktop_config.json

# Remove repository
rm -rf /path/to/smartsuite_mcp_server

# Remove cache (optional)
rm ~/.smartsuite_mcp_cache.db
```

## Next Steps

- **[Quick Start Tutorial](quick-start.md)** - 5-minute walkthrough
- **[Configuration Guide](configuration.md)** - Advanced configuration
- **[User Guide](../guides/user-guide.md)** - Learn how to use the server
- **[Troubleshooting](troubleshooting.md)** - Common issues

## Need Help?

- [Troubleshooting Guide](troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
