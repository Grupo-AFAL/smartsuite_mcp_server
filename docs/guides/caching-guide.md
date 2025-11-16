# Caching Guide

Learn how SmartSuite MCP Server's caching system works and how to use it effectively.

## What is Caching?

The server uses an aggressive SQLite-based caching strategy to:
- **Reduce API calls** by 75%+ (stay within SmartSuite rate limits)
- **Save tokens** by 60%+ (faster, cheaper Claude interactions)
- **Speed up responses** from seconds to milliseconds
- **Enable local querying** with SQL filters on cached data

## How It Works

### Cache-First Strategy

```
┌─────────────┐
│ Your Request│
└──────┬──────┘
       │
       ▼
┌────────────────┐
│ Check Cache    │──► Expired? ──► Fetch from API ──► Update Cache
│ Valid for 4h?  │                                     │
└────────┬───────┘                                     │
       │ Hit! ◄───────────────────────────────────────┘
       ▼
┌──────────────┐
│ Query SQLite │
│ Return Data  │
└──────────────┘
```

**On First Request:**
1. Cache miss detected
2. Fetch ALL records from SmartSuite API (paginated)
3. Store in dynamic SQLite table
4. Set TTL = 4 hours
5. Return requested data

**On Subsequent Requests:**
1. Check cache validity
2. Query local SQLite database
3. Apply filters locally (no API call!)
4. Return results instantly

## Cache Duration (TTL)

Default time-to-live (TTL) varies by resource type:

| Resource Type | Default TTL | Rationale |
|--------------|-------------|-----------|
| **Solutions** | 4 hours | Rarely change |
| **Tables** | 4 hours | Schema stable |
| **Members** | 4 hours | User list stable |
| **Records** | 4 hours | Configurable per table |

Cache expires automatically after TTL. Next request will refresh.

## Cache Behavior by Operation

### Queries (Read Operations)

**Always uses cache** when valid:
- `list_solutions`
- `list_tables`
- `get_table`
- `list_records`
- `get_record`
- `list_members`
- `list_teams`

### Mutations (Write Operations)

**Never uses cache** - always hits API:
- `create_record`
- `update_record`
- `delete_record`
- `add_field`
- `update_field`
- `delete_field`

**Important:** Mutations do NOT invalidate cache. Cache expires naturally by TTL.

## Bypassing the Cache

Force fresh data from API:

```ruby
# Normal request (uses cache)
list_records('tbl_123', 10, 0, fields: ['status'])

# Bypass cache (always fresh)
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true
)
```

**When to bypass:**
- Immediately after creating/updating records
- When you need guaranteed fresh data
- During development/debugging

## Local Filtering

The cache enables powerful local filtering without API calls:

```ruby
# This queries the local SQLite cache - zero API calls!
list_records('tbl_123', 100, 0,
  fields: ['status', 'priority'],
  filter: {
    operator: 'and',
    fields: [
      {field: 'status', comparison: 'is', value: 'Active'},
      {field: 'priority', comparison: 'is_greater_than', value: 3}
    ]
  }
)
```

**Note:** SmartSuite API filters are ignored when using cache. All filtering happens via SQL on cached data.

## Monitoring Cache Performance

### Check Cache Stats

```ruby
get_api_stats
```

Returns:
```json
{
  "summary": {
    "total_calls": 45,        // Total API calls made
    "unique_tables": 5        // Tables with cached data
  },
  "by_endpoint": {...}
}
```

### Cache Hit Rate

Monitor your logs for cache performance:

```
~/.smartsuite_mcp_metrics.log
```

Look for:
- `✓ Cache HIT` - Data served from cache
- `✗ Cache MISS` - Fetched from API

**Target:** >80% cache hit rate for best performance

## Cache Storage

### Location

All cache data stored in:
```
~/.smartsuite_mcp_cache.db
```

Single SQLite file containing:
- Cached solutions, tables, records
- API call logs
- Statistics

### Size Management

The cache grows as you query more tables:
- Each SmartSuite table = 1 SQLite table
- Typical size: 1-50 MB (depends on record count)
- No automatic size limits

**Manual cleanup:**
```bash
# Clear all cache (will rebuild automatically)
rm ~/.smartsuite_mcp_cache.db
```

## Best Practices

### 1. Let the Cache Work

**✅ Good:**
```ruby
# Query once, cache serves future requests
list_records('tbl_123', 10, 0, fields: ['status'])
# ... later ...
list_records('tbl_123', 20, 10, fields: ['status'])  # Uses cache!
```

**❌ Avoid:**
```ruby
# Don't bypass cache unnecessarily
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true  # Wastes API calls
)
```

### 2. Request Minimal Fields

**✅ Good:**
```ruby
# Only fetch fields you need
list_records('tbl_123', 10, 0,
  fields: ['status', 'priority']  // 2 fields = less tokens
)
```

**❌ Avoid:**
```ruby
# Don't fetch all fields if you only need a few
list_records('tbl_123', 10, 0,
  fields: ['status', 'priority', 'description', 'notes', 'comments']
)
```

### 3. Use Pagination Wisely

**✅ Good:**
```ruby
# Start small, fetch more if needed
list_records('tbl_123', 10, 0, fields: ['status'])
# ... user wants more ...
list_records('tbl_123', 10, 10, fields: ['status'])  # Next page
```

**❌ Avoid:**
```ruby
# Don't fetch thousands of records at once
list_records('tbl_123', 5000, 0, fields: ['status'])  // Slow, high tokens
```

### 4. Understand TTL

**✅ Good:**
```ruby
# Accept 4-hour staleness for most queries
list_records('tbl_123', 10, 0, fields: ['status'])
```

**❌ Avoid:**
```ruby
# Don't bypass for every request
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true  // Only when truly needed!
)
```

## Advanced Topics

### Dynamic Table Creation

The cache automatically creates SQLite tables as needed:

```
SmartSuite Table: "Customers" (tbl_abc123)
                    ↓
SQLite Table: cache_tbl_abc123
                    ↓
Columns: id, title, status, created_on, etc.
```

Each SmartSuite table gets its own optimized SQLite schema.

### Schema Evolution

When SmartSuite table structure changes:
1. Existing cache remains valid (old schema)
2. After TTL expires, fresh data fetched
3. Cache table recreated with new schema
4. No manual intervention needed

### Performance Characteristics

**Cache HIT:**
- Latency: ~5-20ms
- API calls: 0
- Tokens: Minimal (plain text)

**Cache MISS:**
- Latency: ~500-2000ms
- API calls: 1-5 (pagination)
- Tokens: Standard

**80% cache hit rate** = **75% fewer API calls** = **Faster and cheaper!**

## Troubleshooting

### Cache Not Working?

Check these:

1. **Cache enabled?**
   ```ruby
   # Check in logs
   grep "Cache layer" ~/.smartsuite_mcp_metrics.log
   ```

2. **TTL expired?**
   ```ruby
   # Cache expires after 4 hours
   # Next request will refresh
   ```

3. **Using bypass_cache?**
   ```ruby
   # Remove bypass_cache parameter
   list_records('tbl_123', 10, 0, fields: ['status'])
   ```

### Stale Data?

If you need fresh data immediately:

```ruby
# Force refresh
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true
)
```

### Cache Too Large?

```bash
# Check size
du -h ~/.smartsuite_mcp_cache.db

# Clear if needed
rm ~/.smartsuite_mcp_cache.db
```

## Next Steps

- **[Performance Guide](performance-guide.md)** - Optimize your queries
- **[Filtering Guide](filtering-guide.md)** - Master local filtering
- **[Architecture: Caching System](../architecture/caching-system.md)** - Deep dive into design
- **[Internals: Cache Implementation](../internals/cache-implementation.md)** - SQLite details

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
