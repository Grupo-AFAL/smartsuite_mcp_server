# Troubleshooting Guide

Common issues and their solutions.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Connection Issues](#connection-issues)
- [API Errors](#api-errors)
- [Cache Issues](#cache-issues)
- [Performance Issues](#performance-issues)

---

## Installation Issues

### Server Not Showing in Claude Desktop

**Symptoms:**
- No 🔌 icon in Claude Desktop
- "smartsuite" not listed in MCP servers

**Solutions:**

1. **Check logs for errors:**
   ```bash
   # macOS
   tail -f ~/Library/Logs/Claude/mcp*.log

   # Windows
   Get-Content "$env:APPDATA\Claude\logs\mcp*.log" -Wait
   ```

2. **Verify absolute path:**
   ```json
   // ❌ Wrong - relative path
   "args": ["./smartsuite_server.rb"]

   // ✅ Correct - absolute path
   "args": ["/Users/yourname/projects/smartsuite_mcp_server/smartsuite_server.rb"]
   ```

3. **Check Ruby version:**
   ```bash
   ruby --version  # Must be 3.0+
   ```

4. **Validate JSON config:**
   Use a JSON validator to check `claude_desktop_config.json` syntax

5. **Restart Claude Desktop:**
   Completely quit (Cmd+Q) and relaunch

### Bundle Install Fails

**Symptoms:**
```
Could not find gem 'sqlite3'
```

**Solution:**
```bash
# Install bundler first
gem install bundler

# Then install dependencies
bundle install

# If still fails, try system-wide
gem install sqlite3
```

### Permission Denied

**Symptoms:**
```
Permission denied - ./smartsuite_server.rb
```

**Solution:**
```bash
chmod +x smartsuite_server.rb
```

---

## Connection Issues

### API Authentication Failed

**Symptoms:**
```
Error: 401 Unauthorized
Invalid API credentials
```

**Solutions:**

1. **Verify API key is correct:**
   - Log in to SmartSuite
   - Settings → API
   - Compare key in config

2. **Check Account ID:**
   - Should be format: `acc_...` or numeric
   - Found in Settings → API

3. **Test credentials manually:**
   ```bash
   curl -H "Authorization: Token YOUR_API_KEY" \
        -H "Account-Id: YOUR_ACCOUNT_ID" \
        https://app.smartsuite.com/api/v1/solutions/
   ```

4. **Regenerate API key:**
   - Settings → API → Generate New Key
   - Update Claude config
   - Restart Claude Desktop

### Rate Limit Exceeded

**Symptoms:**
```
Error: 429 Too Many Requests
Rate limit exceeded
```

**Solutions:**

1. **Enable caching** (should be default):
   ```ruby
   # Uses cache - minimal API calls
   list_records('tbl_123', 10, 0, fields: ['status'])
   ```

2. **Avoid bypass_cache:**
   ```ruby
   # ❌ Avoid - hits API every time
   list_records('tbl_123', 10, 0,
     fields: ['status'],
     bypass_cache: true
   )
   ```

3. **Check API usage:**
   ```ruby
   get_api_stats
   ```

4. **Wait and retry:**
   - SmartSuite limits: 5 requests/second
   - Wait 1 minute and try again

### Network Timeout

**Symptoms:**
```
Error: Request timeout
Connection timed out after 30000ms
```

**Solutions:**

1. **Check internet connection**

2. **Verify SmartSuite is accessible:**
   ```bash
   ping app.smartsuite.com
   ```

3. **Check proxy settings** if behind corporate firewall

4. **Try smaller requests:**
   ```ruby
   # Instead of fetching 1000 records
   list_records('tbl_123', 10, 0, fields: ['status'])
   ```

---

## API Errors

### Table/Record Not Found

**Symptoms:**
```
Error: Table not found: tbl_abc123
Error: Record not found: rec_xyz789
```

**Solutions:**

1. **Verify ID is correct:**
   ```ruby
   # List all tables to find correct ID
   list_tables
   ```

2. **Check permissions:**
   - You may not have access to that table
   - Verify in SmartSuite web app

3. **Table might be deleted:**
   - Check in SmartSuite web app

### Invalid Filter Syntax

**Symptoms:**
```
Error: Invalid filter structure
Comparison operator 'equals' not supported
```

**Solutions:**

1. **Use correct operators:**
   ```ruby
   # ❌ Wrong
   {field: 'status', comparison: 'equals', value: 'Active'}

   # ✅ Correct
   {field: 'status', comparison: 'is', value: 'Active'}
   ```

2. **Check operator compatibility:**
   - See [Filter Operators Reference](../reference/filter-operators.md)
   - Different field types support different operators

3. **Use prompt examples:**
   ```
   Show me how to filter active records
   ```

### Field Not Found

**Symptoms:**
```
Error: Field 'xyz' not found in table
```

**Solutions:**

1. **Get table structure first:**
   ```ruby
   get_table('tbl_abc123')
   ```

2. **Use correct field slug:**
   ```ruby
   # Field slugs are like: s7e8c12e98
   # NOT the label like "Status"
   list_records('tbl_123', 10, 0,
     fields: ['s7e8c12e98']  // Use slug, not label
   )
   ```

3. **Field might not exist:**
   - Check in SmartSuite web app

---

## Cache Issues

### Stale Data

**Symptoms:**
- Data doesn't reflect recent changes
- Created records not showing up

**Solutions:**

1. **Wait for cache to expire** (4 hours)

2. **Bypass cache for fresh data:**
   ```ruby
   list_records('tbl_123', 10, 0,
     fields: ['status'],
     bypass_cache: true
   )
   ```

3. **Clear cache manually:**
   ```bash
   rm ~/.smartsuite_mcp_cache.db
   ```

### Cache Not Working

**Symptoms:**
- Every request hits the API
- No speed improvement

**Solutions:**

1. **Check cache is enabled:**
   ```bash
   grep "Cache layer" ~/.smartsuite_mcp_metrics.log
   ```

2. **Verify cache database exists:**
   ```bash
   ls -lh ~/.smartsuite_mcp_cache.db
   ```

3. **Check disk space:**
   ```bash
   df -h ~
   ```

4. **Review logs for errors:**
   ```bash
   tail -50 ~/Library/Logs/Claude/mcp*.log
   ```

### Cache Too Large

**Symptoms:**
- Slow performance
- Disk space warnings

**Solutions:**

1. **Check cache size:**
   ```bash
   du -h ~/.smartsuite_mcp_cache.db
   ```

2. **Clear cache:**
   ```bash
   rm ~/.smartsuite_mcp_cache.db
   # Will rebuild automatically on next use
   ```

3. **Be selective with queries:**
   ```ruby
   # ❌ Avoid caching huge tables
   list_records('huge_table', 10000, 0, fields: [...])

   # ✅ Query what you need
   list_records('huge_table', 100, 0, fields: ['status', 'priority'])
   ```

---

## Performance Issues

### Slow Responses

**Symptoms:**
- Requests take 5-10+ seconds
- Claude feels sluggish

**Solutions:**

1. **Enable caching** (should be default)

2. **Request fewer fields:**
   ```ruby
   # ❌ Slow - all fields
   list_records('tbl_123', 100, 0, fields: [...20 fields...])

   # ✅ Fast - minimal fields
   list_records('tbl_123', 100, 0, fields: ['status', 'priority'])
   ```

3. **Use pagination:**
   ```ruby
   # ❌ Slow - fetch 1000 at once
   list_records('tbl_123', 1000, 0, fields: ['status'])

   # ✅ Fast - paginate
   list_records('tbl_123', 50, 0, fields: ['status'])
   ```

4. **Check cache hit rate:**
   ```ruby
   get_api_stats
   # Look for "by_endpoint" - repeated endpoints = cache working
   ```

### High Token Usage

**Symptoms:**
- Claude context fills up quickly
- "Context limit reached" errors

**Solutions:**

1. **Request minimal fields:**
   ```ruby
   list_records('tbl_123', 10, 0,
     fields: ['id', 'status']  // Only what you need
   )
   ```

2. **Use smaller limits:**
   ```ruby
   # Start with 10-20 records
   list_records('tbl_123', 10, 0, fields: [...])
   ```

3. **Leverage plain text format:**
   - Server automatically returns plain text (not JSON)
   - 30-50% token savings vs JSON

---

## Debug Mode

### Enable Verbose Logging

Set DEBUG environment variable:

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/path/to/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "...",
        "SMARTSUITE_ACCOUNT_ID": "...",
        "DEBUG": "true"
      }
    }
  }
}
```

Then check logs:
```bash
tail -f ~/Library/Logs/Claude/mcp*.log
```

### Check Server Status

Look for initialization messages in logs:
```
SmartSuite MCP Server starting...
✓ Cache layer initialized: /Users/you/.smartsuite_mcp_cache.db
✓ Session ID: 20251116_123456_abc
✓ Stats tracker sharing cache database
```

---

## Getting Additional Help

### Before Requesting Help

Please provide:

1. **Ruby version:**
   ```bash
   ruby --version
   ```

2. **OS and version:**
   ```bash
   # macOS
   sw_vers

   # Linux
   uname -a
   ```

3. **Error logs:**
   ```bash
   tail -100 ~/Library/Logs/Claude/mcp*.log
   ```

4. **Config (sanitized):**
   ```json
   {
     "mcpServers": {
       "smartsuite": {
         "command": "ruby",
         "args": ["/path/to/smartsuite_server.rb"],
         "env": {
           "SMARTSUITE_API_KEY": "sk_***",  // Redacted
           "SMARTSUITE_ACCOUNT_ID": "acc_***"  // Redacted
         }
       }
     }
   }
   ```

### Support Channels

- **GitHub Issues:** [Create an issue](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- **GitHub Discussions:** [Ask a question](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
- **Documentation:** [Full docs](../README.md)

---

## See Also

- [Installation Guide](installation.md)
- [Configuration Guide](configuration.md)
- [Caching Guide](../guides/caching-guide.md)
- [Performance Guide](../guides/performance-guide.md)
