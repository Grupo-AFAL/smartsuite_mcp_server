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

2. **Use cache (default behavior):**
   ```ruby
   # ✅ Good - uses cache, minimal API calls
   list_records('tbl_123', 10, 0, fields: ['status'])
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
- Updates made in SmartSuite web app not visible

**Solutions:**

1. **Check cache status first:**
   ```ruby
   get_cache_status
   # Shows which tables are cached, when they expire, how many records
   ```

2. **Refresh specific table cache:**
   ```ruby
   # Invalidates cache for one table, then query fresh data
   refresh_cache('records', table_id: 'tbl_123')
   list_records('tbl_123', 10, 0, fields: ['status'])
   ```

3. **Wait for cache to expire** (default TTL: 12 hours for records, 7 days for solutions/tables)

4. **Clear cache manually (nuclear option):**
   ```bash
   rm ~/.smartsuite_mcp_cache.db
   # Will rebuild automatically on next use
   ```

**Understanding cache behavior:**
- `create_record`, `update_record`, `delete_record` do **NOT** automatically invalidate cache
- Cache expires naturally by TTL (default: 12 hours)
- Use `refresh_cache('records', table_id: 'tbl_123')` after mutations to see changes immediately

### Cache Not Working

**Symptoms:**
- Every request hits the API
- No speed improvement
- Low cache hit rate

**Solutions:**

1. **Check cache performance:**
   ```ruby
   get_api_stats(time_range: 'session')
   # Look at cache_performance section:
   # - hit_rate should be >70% after warmup
   # - efficiency_ratio shows cache benefit
   ```

2. **Verify cache database exists:**
   ```bash
   ls -lh ~/.smartsuite_mcp_cache.db
   ```

3. **Check cache status:**
   ```ruby
   get_cache_status
   # Shows all cached tables and their validity
   ```

4. **Check disk space:**
   ```bash
   df -h ~
   ```

5. **Review logs for errors:**
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

## Frequently Asked Questions (FAQ)

### General Questions

#### Q: Do I need to restart Claude Desktop after every code change?

**A:** Yes, but only for server code changes. If you modify `smartsuite_server.rb` or any files in `lib/`, you must:
1. Completely quit Claude Desktop (Cmd+Q / Ctrl+Q)
2. Relaunch Claude Desktop

Config changes in `claude_desktop_config.json` also require a restart.

#### Q: How do I know if the server is working?

**A:** Check for these signs:
1. 🔌 icon appears in Claude Desktop interface
2. "smartsuite" shows in server list
3. Logs show successful initialization:
   ```bash
   tail ~/Library/Logs/Claude/mcp*.log
   # Look for: "SmartSuite MCP Server starting..."
   ```
4. Test with a simple command: "List all my SmartSuite solutions"

#### Q: Can I use multiple SmartSuite accounts?

**A:** Not simultaneously in one config. However, you can:
1. Set up multiple named servers in `claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "smartsuite-work": {
         "env": {
           "SMARTSUITE_API_KEY": "work_key",
           "SMARTSUITE_ACCOUNT_ID": "work_account"
         }
       },
       "smartsuite-personal": {
         "env": {
           "SMARTSUITE_API_KEY": "personal_key",
           "SMARTSUITE_ACCOUNT_ID": "personal_account"
         }
       }
     }
   }
   ```
2. Each will have its own cache database
3. Specify which one to use in your Claude prompts

### Cache Questions

#### Q: When should I use `refresh_cache`?

**A:** Use it when:
- You just created/updated records and need to see changes immediately
- You're debugging and suspect stale data
- You need guaranteed fresh data for critical operations

**Don't use it when:**
- Reading data that doesn't change frequently
- Querying the same data repeatedly
- You're okay with data being up to 12 hours old

**Example:**
```ruby
# After creating a record, refresh cache then query
create_record('tbl_123', {status: 'Active'})
refresh_cache('records', table_id: 'tbl_123')
list_records('tbl_123', 10, 0, fields: ['status'])
```

#### Q: How much disk space does the cache use?

**A:** It depends on your data:
- Typical: 10-50 MB for small workspaces (< 10,000 records)
- Medium: 100-500 MB for mid-size workspaces (< 100,000 records)
- Large: 1-5 GB for large workspaces (> 100,000 records)

Check current size:
```bash
du -h ~/.smartsuite_mcp_cache.db
```

#### Q: Does the cache work across Claude Desktop sessions?

**A:** Yes! The cache persists in `~/.smartsuite_mcp_cache.db`:
- Survives Claude Desktop restarts
- Survives computer reboots
- Only cleared by TTL expiration or manual deletion

#### Q: How do I get fresh data after making changes?

**A:** Use the `refresh_cache` tool to invalidate the cache, then query:

```ruby
# 1. Make your changes
create_record('tbl_123', {status: 'Active'})

# 2. Invalidate the cache for that table
refresh_cache('records', table_id: 'tbl_123')

# 3. Query to get fresh data
list_records('tbl_123', 10, 0, fields: ['status'])
```

**Resource types for `refresh_cache`:**
- `'records'` - Invalidates records for a specific table (requires `table_id`)
- `'tables'` - Invalidates tables (optionally for a specific `solution_id`)
- `'solutions'` - Invalidates all solutions
- `'members'` - Invalidates members cache
- `'teams'` - Invalidates teams cache

### Performance Questions

#### Q: Why is my first query slow?

**A:** First queries populate the cache:
- Initial: 5-15 seconds (fetching + caching all records)
- Subsequent: <1 second (cached data)

This is **normal behavior** - the server aggressively caches entire tables.

#### Q: How do I optimize token usage?

**A:** Follow these best practices:

1. **Request minimal fields:**
   ```ruby
   # ❌ Bad - returns all fields
   list_records('tbl_123', 10, 0, fields: [...30 fields...])

   # ✅ Good - only what you need
   list_records('tbl_123', 10, 0, fields: ['id', 'status', 'priority'])
   ```

2. **Use smaller limits initially:**
   ```ruby
   # Start with 5-10 records to preview
   list_records('tbl_123', 5, 0, fields: [...])
   ```

3. **Leverage plain text format:**
   - Server automatically returns plain text (not JSON)
   - 30-50% token savings
   - No action needed on your part

4. **Use filtering to reduce results:**
   ```ruby
   list_records('tbl_123', 10, 0,
     fields: ['status'],
     filter: {
       operator: 'and',
       fields: [{field: 'status', comparison: 'is', value: 'Active'}]
     }
   )
   ```

#### Q: How can I speed up cache warmup?

**A:** Cache is automatically populated on first access to each table. To pre-warm cache for specific tables, simply query them:

```ruby
# Query tables to populate their cache
list_records('tbl_customers', 1, 0, fields: ['id'])
list_records('tbl_orders', 1, 0, fields: ['id'])
```

Best time to warm cache:
- Start of work session
- After cache refresh
- Before bulk analysis tasks

### API Questions

#### Q: What are SmartSuite's rate limits?

**A:**
- **Standard:** 5 requests/second per user
- **Overage:** 2 requests/second when exceeding monthly allowance
- **Hard limit:** Denied at 125% of monthly limits

The cache layer helps you stay well under these limits.

#### Q: How do I handle "429 Too Many Requests" errors?

**A:**

1. **Enable caching** (should be default) - this is your first line of defense

2. **Check API usage:**
   ```ruby
   get_api_stats(time_range: 'session')
   # Look at by_endpoint to see what's being called
   ```

3. **Use cache efficiently:**
   ```ruby
   # ✅ Good - hits API once, uses cache for subsequent queries
   list_records('tbl_123', 100, 0, fields: [...])
   ```

4. **Wait and retry:** If you hit the limit, wait 60 seconds

#### Q: Can I use this with SmartSuite's API v2 when it releases?

**A:** The server currently uses API v1. When v2 releases:
- We'll evaluate migration path
- May support both versions
- Will communicate breaking changes
- Check GitHub releases for updates

### Error Questions

#### Q: "ArgumentError: table_id is required and cannot be nil or empty" - What does this mean?

**A:** This is a validation error from v1.8+. It means:
- You called a method without providing required parameter
- Example that causes this:
  ```ruby
  list_records(nil, 10, 0)  # table_id is nil
  ```
- Fix by providing the parameter:
  ```ruby
  list_records('tbl_123', 10, 0, fields: ['status'])
  ```

All required parameters are now validated with helpful error messages.

#### Q: "ERROR: You must specify 'fields' parameter" - Why?

**A:** This is intentional token optimization:
- **Purpose:** Prevents accidentally fetching all fields (could be 50+ fields with huge values)
- **Solution:** Always specify which fields you need:
  ```ruby
  list_records('tbl_123', 10, 0, fields: ['status', 'priority'])
  ```
- **Benefit:** Reduces token usage by 60-90%

#### Q: Why do my filters not work with cached data?

**A:** Cache uses SQL queries, not SmartSuite API filters. Filters work via SQL on cached data (full feature support). You shouldn't notice a difference.

If filters don't work as expected:
1. Check operator syntax (use `is`, not `equals`)
2. Verify field slugs are correct
3. Check filter examples: "Show me how to filter active records"

### Data Questions

#### Q: Why don't my created records show up immediately?

**A:** Cache behavior:
- `create_record`, `update_record`, `delete_record` do **NOT** auto-invalidate cache
- Design choice for simplicity and consistency
- Cache expires by TTL (default: 12 hours)

**Solution:** Use `refresh_cache` tool after mutations:
```ruby
# Refresh cache then query
create_record('tbl_123', {status: 'Active'})
refresh_cache('records', table_id: 'tbl_123')
list_records('tbl_123', 10, 0, fields: ['status'])
```

#### Q: Can I query deleted records?

**A:** No:
- Deleted records are not returned by SmartSuite API
- They won't appear in cache
- Cache doesn't track deletions

If you need audit trails, use SmartSuite's built-in activity log.

#### Q: How do I work with linked records?

**A:** Use the `hydrated` parameter (enabled by default):

```ruby
# With hydrated=true (default): Shows readable names
list_records('tbl_orders', 10, 0,
  fields: ['customer', 'product'],
  hydrated: true
)
# Returns: {customer: "John Doe", product: "Widget"}

# With hydrated=false: Shows only IDs
list_records('tbl_orders', 10, 0,
  fields: ['customer', 'product'],
  hydrated: false
)
# Returns: {customer: "rec_abc123", product: "rec_xyz789"}
```

For performance, `hydrated: true` is recommended and default.

---

## See Also

- [Installation Guide](installation.md)
- [Configuration Guide](configuration.md)
- [Caching Guide](../guides/caching-guide.md)
- [Performance Guide](../guides/performance-guide.md)
- [Filter Operators Reference](../guides/filtering-guide.md)
- [API Stats Guide](../api/stats.md)
