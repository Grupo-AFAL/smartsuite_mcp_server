# API Statistics

Complete reference for API usage tracking and monitoring.

## Overview

The server tracks all SmartSuite API calls for monitoring, debugging, and optimization. Statistics help you understand API usage patterns, identify heavy operations, and stay within rate limits.

**Key Features:**
- Track API calls by user, solution, table, method, endpoint
- Session-based tracking with unique session IDs
- Privacy-preserving (API keys hashed)
- Persistent SQLite storage
- Real-time stats and historical data

---

## get_api_stats

Get detailed API call statistics for the current session or all sessions.

### Parameters

None required - returns all tracked statistics.

### Example

```ruby
get_api_stats
```

### Response Format

```
=== API STATISTICS ===

Session: 20251115_143022_abc123
Started: 2025-01-15T14:30:22Z

Summary:
  Total API Calls: 127
  Unique Users: 2
  Unique Solutions: 8
  Unique Tables: 15
  Unique Endpoints: 12

By User (hashed API key):
  a1b2c3d4: 95 calls
  e5f6g7h8: 32 calls

By Solution:
  sol_abc123 (Customer Management): 45 calls
  sol_def456 (Project Tracker): 38 calls
  sol_ghi789 (Sales Pipeline): 22 calls
  [... etc]

By Table:
  tbl_123abc (Customers): 28 calls
  tbl_456def (Tasks): 24 calls
  tbl_789ghi (Orders): 18 calls
  [... etc]

By HTTP Method:
  GET: 87 calls
  POST: 32 calls
  PUT: 6 calls
  DELETE: 2 calls

By Endpoint:
  /api/v1/applications/{id}/records/list/: 56 calls
  /api/v1/solutions/: 18 calls
  /api/v1/applications/: 15 calls
  /api/v1/applications/{id}/: 12 calls
  [... etc]

Top Solutions by Activity:
  1. sol_abc123 - 45 calls
  2. sol_def456 - 38 calls
  3. sol_ghi789 - 22 calls

Top Tables by Activity:
  1. tbl_123abc - 28 calls
  2. tbl_456def - 24 calls
  3. tbl_789ghi - 18 calls
```

### Statistics Breakdown

**Summary Metrics:**
- `total_calls` - Total API requests made
- `unique_users` - Distinct API keys used (hashed)
- `unique_solutions` - Solutions accessed
- `unique_tables` - Tables queried
- `unique_endpoints` - API endpoints called

**By User:**
- Hashed API key (SHA256, first 8 chars)
- Call count per user
- Privacy-preserving identification

**By Solution:**
- Solution ID and name
- Calls accessing that solution
- Helps identify heavily-used workspaces

**By Table:**
- Table ID and name
- Calls accessing that table
- Identifies hot tables

**By HTTP Method:**
- GET (read operations)
- POST (create/query operations)
- PUT (update operations)
- DELETE (delete operations)

**By Endpoint:**
- Full API endpoint path
- Call count per endpoint
- Identifies most-used operations

### Use Cases

**1. Monitor API Usage:**
```ruby
# Check current usage
get_api_stats

# Review call counts
# Stay within rate limits (5 req/sec)
```

**2. Identify Performance Bottlenecks:**
```ruby
# Get stats
get_api_stats

# Look for:
# - High call counts on specific tables
# - Repeated endpoint calls (cache misses?)
# - Heavy solutions
```

**3. Optimize Caching:**
```ruby
# Check stats
get_api_stats

# Look at by_endpoint:
# - /records/list/ called 50 times
# - Consider caching strategy

# Verify cache is enabled
list_records('tbl_heavy', 10, 0, fields: ['status'])
# Should use cache on subsequent calls
```

**4. Audit API Activity:**
```ruby
# Get stats for session
get_api_stats

# Review:
# - Which users made calls
# - What solutions were accessed
# - What operations were performed
```

**5. Debug Rate Limit Issues:**
```ruby
# If hitting rate limits (429 errors)
get_api_stats

# Check:
# - Total calls (should be < 300/minute)
# - Endpoint distribution (any repeated calls?)
# - Consider caching or reducing operations
```

### Session Tracking

Each server instance gets a unique session ID:
```
Format: YYYYMMDD_HHMMSS_random
Example: 20251115_143022_abc123
```

**Benefits:**
- Track usage across server restarts
- Compare performance between sessions
- Historical analysis

### Privacy

**API key hashing:**
- Uses SHA256 hash
- Only first 8 characters stored
- Original key never persisted
- Enables user tracking without exposing credentials

**Example:**
```
Original: sk_live_abc123def456ghi789...
Hashed:   a1b2c3d4
```

### Storage

**Location:**
```
~/.smartsuite_mcp_cache.db
```

**Tables:**
- `api_calls` - Individual call logs
- `api_stats_summary` - Aggregated statistics

**Retention:**
- All calls logged
- No automatic cleanup
- Manual cleanup: `reset_api_stats`

### Notes

- **No cache** - always returns current stats from database
- **Session-based** - stats include current session only by default
- **Privacy-preserving** - API keys hashed
- **Persistent** - survives server restarts

---

## reset_api_stats

Clear all API call statistics and start fresh.

### Parameters

None required - resets all statistics.

### Example

```ruby
reset_api_stats
```

### Response Format

```
=== API STATISTICS RESET ===

All API call statistics have been cleared.

Previous stats:
  Total Calls: 127
  Session: 20251115_143022_abc123

New session started:
  Session ID: 20251115_160945_xyz789
  Total Calls: 0

Statistics tracking continues with new session.
```

### What Gets Reset

**Cleared:**
- All logged API calls
- Summary statistics
- User call counts
- Solution call counts
- Table call counts
- Endpoint call counts

**Preserved:**
- Server configuration
- Cache data (separate from stats)
- MCP protocol state

**New session:**
- Fresh session ID generated
- Call counter reset to 0
- Tracking continues immediately

### Use Cases

**1. Start Fresh After Testing:**
```ruby
# After development/testing
get_api_stats  # Shows 500+ calls from testing

# Clear stats
reset_api_stats

# Continue with clean slate
```

**2. Periodic Cleanup:**
```ruby
# Monthly stats cleanup
reset_api_stats

# Prevents stats database from growing too large
```

**3. Performance Baseline:**
```ruby
# Reset before performance test
reset_api_stats

# Run operations
list_records(...)
create_record(...)
# ... etc

# Check stats
get_api_stats
# See exact call counts from test
```

**4. Debug Session:**
```ruby
# Reset before debugging
reset_api_stats

# Reproduce issue
# ... operations ...

# Check stats for that specific issue
get_api_stats
# See only calls from debugging session
```

### Notes

- **Immediate** - stats cleared instantly
- **Cannot be undone** - no backup created
- **New session** - tracking continues with new ID
- **Cache unaffected** - separate from statistics

---

## Common Patterns

### Monitor Rate Limits

```ruby
# Before heavy operation
get_api_stats
# Note: total_calls = 250

# Perform operations
# ... bulk queries ...

# Check again
get_api_stats
# Note: total_calls = 380

# Calculate: 380 - 250 = 130 calls
# Rate: 130 calls over X seconds
# Ensure < 5 req/sec average
```

### Optimize Cache Usage

```ruby
# Check initial stats
get_api_stats
# by_endpoint shows: /records/list/ = 50 calls

# Enable caching (should be default)
list_records('tbl_heavy', 10, 0, fields: ['status'])

# Query again (should use cache)
list_records('tbl_heavy', 20, 0, fields: ['status'])

# Check stats again
get_api_stats
# by_endpoint should still show: /records/list/ = 50 calls
# (no increase = cache working)
```

### Identify Hot Tables

```ruby
# Get stats
get_api_stats

# Review "By Table" section
# Find tables with highest call counts

# Optimize hot tables:
# - Ensure caching enabled
# - Reduce query frequency
# - Request minimal fields
```

### Debug Repeated Calls

```ruby
# Reset stats
reset_api_stats

# Reproduce issue
# ... operations that seem slow ...

# Check stats
get_api_stats

# Look for repeated endpoint calls:
# /records/list/ = 20 calls to same table?
# Indicates: cache miss or frequent refresh_cache usage
# Fix: ensure caching enabled, reduce cache refreshes
```

### Session Performance Comparison

```ruby
# Session 1: Without caching
reset_api_stats
# ... operations ...
get_api_stats
# Note: total_calls = 150

# Session 2: With caching
reset_api_stats
list_records('tbl_123', 10, 0, fields: ['status'])  # Cache miss
list_records('tbl_123', 20, 0, fields: ['status'])  # Cache hit
list_records('tbl_123', 30, 0, fields: ['status'])  # Cache hit
get_api_stats
# Note: total_calls = 1 (just the initial cache fetch)
# Improvement: 150 → 1 calls (99.3% reduction)
```

---

## Best Practices

### 1. Monitor Regularly

**✅ Good:**
```ruby
# Check stats periodically during development
get_api_stats

# Look for:
# - Unexpected high call counts
# - Repeated calls to same endpoint
# - Heavy solutions/tables
```

**❌ Avoid:**
```ruby
# Never checking stats
# Miss opportunities to optimize
# Hit rate limits unexpectedly
```

### 2. Reset After Testing

**✅ Good:**
```ruby
# After testing session
reset_api_stats

# Prevents test calls from polluting production stats
```

**❌ Avoid:**
```ruby
# Mixing test and production stats
# Hard to distinguish real usage patterns
```

### 3. Use Stats to Optimize

**✅ Good:**
```ruby
# Review stats
get_api_stats
# Find: tbl_customers called 50 times

# Optimize with caching
list_records('tbl_customers', 10, 0, fields: ['status'])
# Subsequent calls use cache (0 API calls)
```

**❌ Avoid:**
```ruby
# Ignore high call counts
# Continue with inefficient patterns
```

### 4. Track Session Performance

**✅ Good:**
```ruby
# Start session
reset_api_stats

# Run operations
# ... work ...

# Review session
get_api_stats
# Analyze session-specific patterns
```

**❌ Avoid:**
```ruby
# Never resetting
# All sessions mixed together
# Hard to analyze specific workflows
```

---

## Understanding the Data

### Call Count Targets

**Healthy usage:**
- < 100 calls/session for typical workflows
- 80%+ cache hit rate on `list_records`
- < 5 req/sec average

**Needs optimization:**
- > 300 calls/session
- Low cache hit rate (repeated calls to same endpoint)
- Bursts > 5 req/sec

### SmartSuite Rate Limits

**Standard tier:**
- 5 requests/second per user
- ~300 requests/minute
- ~18,000 requests/hour

**When exceeding:**
- 2 requests/second (throttled)
- 429 errors returned
- Hard limit at 125% of monthly quota

**How to stay within limits:**
- Use caching (default: enabled)
- Batch operations when possible
- Request minimal fields
- Use `refresh_cache` tool sparingly (only when needed)

### Cache Effectiveness

**Check cache performance:**
```ruby
get_api_stats
# by_endpoint: /records/list/ = X calls
```

**Good cache usage:**
- First call to table: Cache MISS (1 API call)
- Subsequent calls: Cache HIT (0 API calls)
- X should be ≈ number of unique tables queried

**Poor cache usage:**
- X = total number of list_records calls
- Indicates cache disabled or always bypassed

---

## Error Handling

### Stats Not Available

```
Error: Stats database not initialized
```

**Solution:**
- Stats should initialize automatically
- Check ~/.smartsuite_mcp_cache.db exists
- Restart server if needed

### Database Locked

```
Error: Database is locked
```

**Solution:**
- Another process accessing database
- Wait and retry
- Check for hung processes

---

## Related Documentation

- **[Caching Guide](../guides/caching-guide.md)** - Optimize API usage
- **[Performance Guide](../guides/performance-guide.md)** - Best practices
- **[Troubleshooting Guide](../getting-started/troubleshooting.md)** - Rate limit issues

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
