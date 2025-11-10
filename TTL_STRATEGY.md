# TTL Strategy for Record Caching

## Overview

Since we're using an **aggressive fetch strategy** (fetch ALL records from a table at once), the TTL is **table-based**, not field-based.

---

## Strategy

### All Records Expire Together

When we fetch records from a SmartSuite table:
1. **Fetch all records** from the table in one operation (potentially paginated)
2. **Store all records** in the cache table with the same `expires_at` timestamp
3. **Query the cache** until expiration
4. **Re-fetch all records** when TTL expires

### TTL is Per-Table, Not Per-Field

```ruby
# Wrong: Different TTLs for different field types
# This doesn't make sense when we fetch all records together
cache.set_record(record_id, {
  status: {value: 'Active', ttl: 6.hours},
  revenue: {value: 50000, ttl: 4.hours}
})

# Right: One TTL for all records in a table
cache.cache_table_records(table_id, records, ttl: 8.hours)
# All records from this table expire at the same time
```

---

## Implementation

### Cache Table Schema

```sql
CREATE TABLE cache_records_abc123 (
  id TEXT PRIMARY KEY,

  -- All the fields...
  project_name TEXT,
  status TEXT,
  revenue REAL,
  due_date INTEGER,

  -- Metadata
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL  -- Same for all records in this table
);

CREATE INDEX idx_expires_at ON cache_records_abc123(expires_at);
```

### Fetching Strategy

```ruby
def fetch_and_cache_records(table_id)
  # Get table-specific TTL configuration
  ttl = get_table_ttl(table_id)

  # Fetch ALL records from SmartSuite
  records = fetch_all_records_paginated(table_id)

  # Calculate expiration time (same for all records)
  expires_at = Time.now.to_i + ttl

  # Store all records with same expiration
  records.each do |record|
    insert_record_into_cache_table(
      table_id,
      record,
      cached_at: Time.now.to_i,
      expires_at: expires_at  # Same for all
    )
  end
end
```

### Checking Expiration

```ruby
def get_cached_records(table_id, filters = {})
  # Check if any record is expired
  # (If one is expired, they all are since they have the same expires_at)

  sample_record = db.execute(
    "SELECT expires_at FROM cache_records_#{sanitize_table_name(table_id)} LIMIT 1"
  ).first

  if sample_record.nil? || sample_record['expires_at'] < Time.now.to_i
    # Cache is empty or expired - re-fetch all records
    fetch_and_cache_records(table_id)
  end

  # Now query the cache
  query_cache_table(table_id, filters)
end
```

Or simpler, just check in the query:

```ruby
def get_cached_records(table_id, filters = {})
  # Try to get from cache
  results = query_cache_table(table_id, filters)

  # If empty or expired, re-fetch
  if results.empty? || results.first['expires_at'] < Time.now.to_i
    fetch_and_cache_records(table_id)
    results = query_cache_table(table_id, filters)
  end

  results
end
```

---

## TTL Configuration

### Default TTLs by Table Type

Based on expected mutation frequency:

```ruby
DEFAULT_TABLE_TTL = {
  # High mutation (project management, tasks)
  high_mutation: 1 * 3600,      # 1 hour

  # Medium mutation (CRM, sales pipeline)
  medium_mutation: 4 * 3600,    # 4 hours

  # Low mutation (reference data, catalogs)
  low_mutation: 12 * 3600,      # 12 hours

  # Very low mutation (historical data, archives)
  very_low_mutation: 24 * 3600  # 24 hours
}
```

### Table-Specific Configuration

Store in database for easy updates:

```sql
CREATE TABLE cache_ttl_config (
  table_id TEXT PRIMARY KEY,
  ttl_seconds INTEGER NOT NULL DEFAULT 14400,  -- 4 hours default
  mutation_level TEXT,  -- 'high', 'medium', 'low', 'very_low'
  notes TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (table_id) REFERENCES tables(id)
);

-- Examples:
INSERT INTO cache_ttl_config (table_id, ttl_seconds, mutation_level, notes, updated_at)
VALUES
  ('table_tasks', 3600, 'high', 'Active project tasks, updated frequently', 1704902400),
  ('table_customers', 14400, 'medium', 'Customer data, moderate updates', 1704902400),
  ('table_products', 43200, 'low', 'Product catalog, rarely changes', 1704902400),
  ('table_archive', 86400, 'very_low', 'Historical data, read-only', 1704902400);
```

### Getting Table TTL

```ruby
def get_table_ttl(table_id)
  # Check for table-specific configuration
  config = db.execute(
    "SELECT ttl_seconds FROM cache_ttl_config WHERE table_id = ?",
    table_id
  ).first

  if config
    config['ttl_seconds']
  else
    # Default: 4 hours
    DEFAULT_TABLE_TTL[:medium_mutation]
  end
end
```

---

## Cache Invalidation

### Manual Invalidation (After Mutations)

When we create/update/delete a record via the MCP server:

```ruby
def create_record(table_id, record_data)
  # Create record via SmartSuite API
  result = api_request(:post, "applications/#{table_id}/records/", body: record_data)

  # Invalidate the entire table cache
  invalidate_table_cache(table_id)

  result
end

def invalidate_table_cache(table_id)
  sql_table_name = "cache_records_#{sanitize_table_name(table_id)}"

  # Option 1: Delete all records (forces re-fetch)
  db.execute("DELETE FROM #{sql_table_name}")

  # Option 2: Set expires_at to past (forces re-fetch on next query)
  db.execute(
    "UPDATE #{sql_table_name} SET expires_at = 0"
  )
end
```

### Auto-Refresh on Expiration

No special invalidation needed - just let TTL expire naturally and re-fetch on next query.

---

## MCP Tool: Manage Cache TTL

Expose cache management via MCP tools:

```ruby
{
  "name": "set_table_cache_ttl",
  "description": "Configure cache TTL for a specific table",
  "inputSchema": {
    "type": "object",
    "properties": {
      "table_id": {
        "type": "string",
        "description": "SmartSuite table ID"
      },
      "ttl_hours": {
        "type": "number",
        "description": "Cache duration in hours (e.g., 4, 12, 24)"
      },
      "mutation_level": {
        "type": "string",
        "enum": ["high", "medium", "low", "very_low"],
        "description": "Expected mutation frequency"
      }
    },
    "required": ["table_id", "ttl_hours"]
  }
}

{
  "name": "get_cache_status",
  "description": "Get cache status for tables",
  "inputSchema": {
    "type": "object",
    "properties": {
      "table_id": {
        "type": "string",
        "description": "Optional: specific table ID"
      }
    }
  }
}

# Returns:
{
  "tables": [
    {
      "table_id": "table_abc123",
      "table_name": "Projects",
      "record_count": 150,
      "cached_at": "2025-01-10T14:30:00Z",
      "expires_at": "2025-01-10T18:30:00Z",
      "ttl_hours": 4,
      "status": "valid",  # "valid", "expired", "empty"
      "time_remaining": "3h 45m"
    }
  ]
}

{
  "name": "invalidate_table_cache",
  "description": "Force invalidation of table cache (re-fetch on next query)",
  "inputSchema": {
    "type": "object",
    "properties": {
      "table_id": {
        "type": "string",
        "description": "Table ID to invalidate"
      }
    },
    "required": ["table_id"]
  }
}
```

---

## Benefits of Table-Based TTL

1. ✅ **Simpler logic** - all records expire together
2. ✅ **Efficient re-fetching** - one bulk fetch instead of individual records
3. ✅ **Consistent state** - all records are from the same point in time
4. ✅ **Easy invalidation** - delete/expire entire table cache after mutations
5. ✅ **Predictable** - know exactly when cache will refresh
6. ✅ **Configurable** - adjust TTL per table based on actual mutation patterns

---

## Example Workflow

### Initial Query (Cache Miss)

```
User: "Show me active projects with revenue > $50k"

1. Check cache: SELECT * FROM cache_records_abc123 WHERE status = 'Active' AND revenue > 50000
   → Empty (no cache)

2. Fetch all records from SmartSuite:
   GET /api/v1/applications/abc123/records/list/
   → Returns 150 records

3. Store in cache with TTL = 4 hours:
   INSERT INTO cache_records_abc123 (..., cached_at, expires_at)
   VALUES (..., 1704902400, 1704916800)  -- All records same expiration

4. Query cache and return results:
   SELECT * FROM cache_records_abc123 WHERE status = 'Active' AND revenue > 50000
   → Returns 12 projects
```

### Subsequent Queries (Cache Hit)

```
User: "Show me projects due this week"

1. Check cache: SELECT * FROM cache_records_abc123 WHERE due_date BETWEEN X AND Y
   → Cache valid (expires_at = 1704916800 > now = 1704905000)
   → Returns 8 projects (no API call!)

User: "Show me projects assigned to John"

2. Query cache again: SELECT * FROM cache_records_abc123 WHERE assigned_to LIKE '%john_id%'
   → Cache still valid
   → Returns 15 projects (no API call!)
```

### Cache Expiration (Re-fetch)

```
4 hours later...

User: "Show me active projects"

1. Check cache: SELECT * FROM cache_records_abc123 WHERE status = 'Active'
   → Results found, but expires_at = 1704916800 < now = 1704920000 (expired!)

2. Re-fetch all records from SmartSuite:
   GET /api/v1/applications/abc123/records/list/
   → Returns 152 records (2 new records added)

3. Update cache with new TTL:
   DELETE FROM cache_records_abc123;  -- Clear old data
   INSERT INTO cache_records_abc123 (..., cached_at, expires_at)
   VALUES (..., 1704920000, 1704934400)  -- New 4-hour window

4. Query updated cache:
   SELECT * FROM cache_records_abc123 WHERE status = 'Active'
   → Returns 14 projects (includes 2 new ones)
```

### Manual Invalidation (After Mutation)

```
User: "Create a new project"

1. Create via API:
   POST /api/v1/applications/abc123/records/
   → Record created

2. Invalidate cache:
   UPDATE cache_records_abc123 SET expires_at = 0;
   (or DELETE FROM cache_records_abc123;)

3. Next query will trigger re-fetch:
   User: "Show me all projects"
   → Cache expired (expires_at = 0)
   → Re-fetch all records
   → Includes the newly created project
```

---

## Summary

### Key Points

1. **TTL is per-table, not per-field** - all records from a table share the same expiration
2. **Configurable per table** - set different TTLs based on mutation frequency
3. **Simple invalidation** - expire/delete entire table cache after mutations
4. **Efficient** - one bulk fetch, many cached queries
5. **Default: 4 hours** - reasonable balance between freshness and API reduction

### Default Configuration

```ruby
DEFAULT_TTL = 4 * 3600  # 4 hours

# Recommended TTLs by use case:
# - Real-time dashboards: 1 hour
# - Regular work tables: 4 hours
# - Reference data: 12 hours
# - Historical/archive: 24 hours
```

---

*TTL Strategy v2.0 - Table-Based Expiration*
