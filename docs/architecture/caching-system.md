# Caching System Architecture

Deep dive into the SQLite-based caching implementation.

## Overview

The caching system is the core performance optimization in SmartSuite MCP Server. It uses SQLite to create a local database that mirrors SmartSuite tables, enabling instant queries and reducing API calls by 75%+.

---

## Design Goals

1. **Minimize API Calls** - Cache aggressively, query locally
2. **Instant Responses** - Milliseconds instead of seconds
3. **Automatic Management** - No manual cache invalidation
4. **Schema Evolution** - Handle field changes gracefully
5. **Persistent Storage** - Survive server restarts

---

## Architecture

### Single Database File

```
~/.smartsuite_mcp_cache.db
```

**Contains:**
- Dynamic tables (one per SmartSuite table)
- Cache metadata (TTL, table info)
- API call logs
- Statistics summaries

**Benefits:**
- Simple deployment (one file)
- Easy backup/deletion
- Atomic transactions
- No configuration

### Dynamic Table Creation

**Pattern:** One SQLite table per SmartSuite table

```ruby
SmartSuite Table: "Projects" (tbl_abc123)
         ↓
SQLite Table: cache_tbl_abc123
         ↓
Columns: id, title, status, priority, due_date, _cached_at
```

**Schema Generation:**
```ruby
def create_cache_table(table_id, structure)
  # Parse SmartSuite field structure
  columns = structure.map do |field|
    {
      name: field[:slug],
      type: sqlite_type_for(field[:field_type])
    }
  end

  # Create table with proper types
  sql = <<~SQL
    CREATE TABLE IF NOT EXISTS cache_#{table_id} (
      id TEXT PRIMARY KEY,
      #{columns.map { |c| "#{c[:name]} #{c[:type]}" }.join(',\n  ')},
      _cached_at TEXT NOT NULL
    )
  SQL

  db.execute(sql)
end
```

**Type Mapping:**
```ruby
TEXT → textfield, emailfield, phoneField, etc.
INTEGER → numberfield, ratingfield
REAL → currencyfield, percentfield
DATETIME → datefield, duedatefield, firstcreatedfield
```

### TTL Implementation

**Approach:** Table-based TTL (all records expire together)

```ruby
# Cache metadata
CREATE TABLE cache_metadata (
  table_id TEXT PRIMARY KEY,
  cached_at TEXT NOT NULL,
  ttl_seconds INTEGER DEFAULT 14400,  -- 4 hours
  record_count INTEGER,
  expires_at TEXT NOT NULL
)
```

**Check validity:**
```ruby
def cache_valid?(table_id)
  row = db.execute(<<~SQL, [table_id])
    SELECT expires_at FROM cache_metadata
    WHERE table_id = ?
  SQL

  return false if row.empty?

  expires_at = DateTime.parse(row[0]['expires_at'])
  DateTime.now < expires_at
end
```

**Benefits:**
- Simple implementation
- No per-record overhead
- Batch expiration (efficient)
- Configurable TTL

### Query Builder

**CacheQuery:** Chainable SQL builder

```ruby
query = CacheQuery.new(db, table_id)
  .where(field: 'status', operator: 'is', value: 'Active')
  .where(field: 'priority', operator: 'is_greater_than', value: 3)
  .order_by('due_date', 'ASC')
  .limit(10)
  .offset(0)

results = query.execute
```

**SQL Generation:**
```ruby
class CacheQuery
  def where(field:, operator:, value:)
    @conditions << {field: field, operator: operator, value: value}
    self
  end

  def build_sql
    <<~SQL
      SELECT #{@fields.join(', ')}
      FROM cache_#{@table_id}
      WHERE #{build_where_clause}
      ORDER BY #{build_order_clause}
      LIMIT #{@limit}
      OFFSET #{@offset}
    SQL
  end
end
```

**Operator Translation:**
```ruby
'is' → "field = ?"
'is_not' → "field != ?"
'contains' → "field LIKE '%' || ? || '%'"
'is_greater_than' → "field > ?"
'is_less_than' → "field < ?"
'is_empty' → "field IS NULL"
'has_any_of' → "field IN (?, ?, ...)"
```

---

## Cache Operations

### 1. Cache Miss → Fetch & Store

```ruby
def get_records(table_id, limit, offset, fields:, filter: nil)
  # Check cache
  unless cache_valid?(table_id)
    # Cache MISS - fetch from API
    refresh_cache(table_id)
  end

  # Query cached data
  query_cache(table_id, limit, offset, fields: fields, filter: filter)
end

def refresh_cache(table_id)
  # 1. Get table structure
  structure = api_get_table(table_id)

  # 2. Create/recreate SQLite table
  create_cache_table(table_id, structure)

  # 3. Fetch ALL records (paginated)
  all_records = []
  offset = 0
  loop do
    batch = api_list_records(table_id, limit: 1000, offset: offset)
    break if batch.empty?

    all_records.concat(batch)
    offset += batch.length
  end

  # 4. Store in SQLite
  db.transaction do
    all_records.each do |record|
      insert_record(table_id, record)
    end
  end

  # 5. Update metadata
  update_cache_metadata(table_id, all_records.length)
end
```

### 2. Cache Hit → Query SQLite

```ruby
def query_cache(table_id, limit, offset, fields:, filter:)
  query = CacheQuery.new(db, table_id)
    .select(fields)
    .limit(limit)
    .offset(offset)

  # Apply filter if present
  if filter
    apply_filter(query, filter)
  end

  query.execute
end
```

### 3. Cache Invalidation

**Approach:** No invalidation on mutations

**Reasoning:**
- Simpler implementation
- Avoids edge cases
- TTL ensures eventual consistency
- User can bypass cache when needed

**On create/update/delete:**
```ruby
# Mutation happens
api_create_record(table_id, data)

# Cache NOT touched
# Expires naturally after 4 hours
# User can refresh: refresh_cache('records', table_id: 'tbl_123')
```

---

## Schema Evolution

### Handling Field Changes

**Scenario:** User adds/removes fields in SmartSuite

**Solution:** Automatic re-caching on next query

```ruby
def cache_valid?(table_id)
  # Check TTL
  return false if ttl_expired?(table_id)

  # Check schema match
  cached_schema = get_cached_schema(table_id)
  current_schema = api_get_table(table_id)

  return false if schemas_differ?(cached_schema, current_schema)

  true
end
```

**When schema changes:**
1. Cache marked invalid
2. Next query triggers refresh
3. New table created with updated schema
4. All records re-fetched
5. Cache valid again

**Benefits:**
- Automatic adaptation
- No manual intervention
- Data stays consistent

---

## Performance Characteristics

### Cache Hit

```
Time: 5-20ms
API calls: 0
Process:
  1. Check TTL (1ms)
  2. Build SQL (1ms)
  3. Execute query (3-18ms)
  4. Format results (1-2ms)
```

### Cache Miss

```
Time: 500-2000ms (first time)
API calls: 1-5 (pagination)
Process:
  1. Check TTL (1ms)
  2. Fetch structure (200ms)
  3. Create table (10ms)
  4. Fetch records (300-1500ms, paginated)
  5. Store in SQLite (50-200ms)
  6. Update metadata (5ms)
  7. Query cache (5-20ms)
```

### Large Tables

**100,000+ records:**
- First query: 3-10 seconds (fetch + store)
- Subsequent queries: 20-50ms
- Cache size: 10-50 MB

**Strategy:**
- Show loading indicator on first query
- Subsequent queries instant
- User benefits from cache for 4 hours

---

## Storage Management

### Cache Size

**Typical workspace:**
- 10 tables × 1,000 records = ~1-5 MB

**Large workspace:**
- 50 tables × 10,000 records = ~50-100 MB

**Very large:**
- 100 tables × 100,000 records = ~500 MB - 1 GB

### Cleanup

**Manual:**
```bash
rm ~/.smartsuite_mcp_cache.db
```

**Automatic:** None (by design)
- Cache provides value
- Disk space typically not constrained
- User controls via `reset_api_stats`

### Monitoring

```ruby
# Check cache size
File.size('~/.smartsuite_mcp_cache.db')

# Check table count
db.execute("SELECT COUNT(*) FROM cache_metadata")

# Check record counts per table
db.execute("SELECT table_id, record_count FROM cache_metadata")
```

---

## Edge Cases

### Empty Tables

```ruby
# Table exists but has no records
refresh_cache(table_id)  # Fetches 0 records
update_cache_metadata(table_id, 0)  # Stores count: 0

# Query returns empty
query_cache(table_id)  # Returns []
```

### Deleted Tables

```ruby
# Table deleted in SmartSuite
cache_valid?(table_id)  # Still true (cache exists)
query_cache(table_id)  # Returns cached data (stale)

# After TTL expires:
refresh_cache(table_id)  # API returns 404
# Handle: Clear cache for this table
```

### Concurrent Access

**Scenario:** Multiple queries to same uncached table

**Solution:** SQLite handles locking
```ruby
# Query 1 starts refresh
refresh_cache(table_id)  # Acquires write lock

# Query 2 waits
refresh_cache(table_id)  # Blocks until Query 1 completes

# Both queries succeed
```

---

## Implementation Details

### Database Schema

```sql
-- Cache metadata
CREATE TABLE cache_metadata (
  table_id TEXT PRIMARY KEY,
  cached_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  ttl_seconds INTEGER DEFAULT 14400,
  record_count INTEGER,
  schema_hash TEXT
);

-- Dynamic tables (one per SmartSuite table)
CREATE TABLE cache_tbl_abc123 (
  id TEXT PRIMARY KEY,
  title TEXT,
  status TEXT,
  priority INTEGER,
  due_date TEXT,
  _cached_at TEXT NOT NULL
);

-- API stats (shares same database)
CREATE TABLE api_calls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  user_hash TEXT NOT NULL,
  solution_id TEXT,
  table_id TEXT,
  http_method TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  timestamp TEXT NOT NULL
);
```

### Cache Key Generation

```ruby
# Table cache key = table_id
cache_key = "tbl_abc123"

# SQLite table name
sqlite_table = "cache_#{cache_key}"

# Metadata lookup
metadata = db.execute(
  "SELECT * FROM cache_metadata WHERE table_id = ?",
  [cache_key]
)
```

### Timestamp Format

**ISO 8601 (TEXT):**
```ruby
cached_at: "2025-01-15T14:30:00Z"
expires_at: "2025-01-15T18:30:00Z"  # +4 hours
```

**Benefits:**
- Human-readable in database
- Sortable
- Timezone-aware
- Standard format

---

## Comparison with Alternatives

### In-Memory Cache (Redis, Memcached)

**Pros:**
- Faster (RAM vs disk)
- Built-in TTL

**Cons:**
- Lost on restart
- Requires separate server
- More complex setup

**Why SQLite:**
- Persistent (survives restarts)
- No server required
- Good enough performance (5-20ms)
- Single file deployment

### File-Based Cache

**Pros:**
- Simple (one file per table)

**Cons:**
- No querying capability
- No transactions
- Harder to maintain

**Why SQLite:**
- SQL querying
- ACID transactions
- Single file
- Built into Ruby

### No Cache

**Pros:**
- Always fresh data
- Simple implementation

**Cons:**
- Every query hits API (slow)
- Rate limit issues
- Poor user experience

**Why caching wins:**
- 99% faster responses
- 75% fewer API calls
- Better UX

---

## Future Enhancements

### Potential Improvements

1. **Smart TTL** - Different TTL per table based on update frequency
2. **Partial Updates** - Update changed records instead of full refresh
3. **Background Refresh** - Refresh cache before expiry
4. **Cache Warming** - Pre-cache frequently accessed tables
5. **Compression** - Compress large text fields

### Currently Not Implemented

1. **Cache invalidation on mutations** - By design (simplicity)
2. **Automatic cleanup** - By design (storage not constrained)
3. **Cache size limits** - By design (user controls)
4. **Multi-user support** - Not needed (single-user design)

---

## Related Documentation

- **[Architecture Overview](overview.md)** - System architecture
- **[User Guide: Caching](../guides/caching-guide.md)** - User-facing caching docs
- **[Performance Guide](../guides/performance-guide.md)** - Performance optimization
- **[Data Flow](data-flow.md)** - How data moves through the system

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
