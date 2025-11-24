# Design Decisions

Rationale behind key architectural and implementation choices in SmartSuite MCP Server.

## Overview

This document explains **why** specific design decisions were made, covering trade-offs, alternatives considered, and reasoning behind the current implementation.

**Topics covered:**
- Caching strategy
- Token optimization
- Protocol choices
- Technology stack
- Error handling
- Performance trade-offs

---

## 1. Cache-First Strategy with No Invalidation

### Decision

**Cache aggressively with table-based TTL (4 hours), no invalidation on mutations**

### Rationale

**Problem:** SmartSuite API has rate limits (5 req/sec), and repeated queries are slow

**Options considered:**

**A) No caching** ❌
- Always fresh data
- Simple implementation
- **Cons:** Slow (1-2 seconds per query), high API usage, poor UX

**B) Cache with invalidation on mutations** ❌
- Fresh data after changes
- Reasonable performance
- **Cons:** Complex, edge cases (concurrent writes, failed invalidations), mutation tracking overhead

**C) Cache-first with TTL, no invalidation** ✅ **CHOSEN**
- Simple implementation
- Predictable behavior
- Excellent performance (99% faster)
- **Cons:** Stale data possible (mitigated by TTL + bypass option)

### Implementation

```ruby
def list_records(table_id, limit, offset, fields:, filter:)
  # Check cache validity
  unless cache_valid?(table_id)
    # Cache MISS - fetch from API
    populate_cache(table_id)
  end

  # Query cached data
  query_cache(table_id, limit, offset, fields: fields, filter: filter)
end
```

**Key points:**
1. **Default:** Always use cache (5-20ms responses)
2. **Cache miss:** Fetch ALL records, cache, then query (one-time cost)
3. **Mutations:** Don't invalidate (cache expires naturally)
4. **Override:** User can use `refresh_cache` tool to invalidate cache

### Trade-offs

**Pros:**
- ✅ 75%+ API call reduction
- ✅ 99% faster responses (5ms vs 1000ms)
- ✅ Simple implementation (no invalidation logic)
- ✅ Predictable behavior (TTL-based)
- ✅ Enables local SQL filtering

**Cons:**
- ⚠️ Potential stale data (up to 4 hours)
- ⚠️ User must know to bypass cache after mutations
- ⚠️ First query slow (fetch all records)

**Mitigation:**
- Claude can request fresh data after mutations
- TTL is configurable
- Bypass cache option always available

### Why Not Other Strategies?

**Write-through cache:**
- Would need to update cache on every mutation
- Complex: what if update fails? Partial updates?
- Still doesn't help with concurrent writes

**Cache invalidation on mutations:**
- "There are only two hard things in Computer Science: cache invalidation and naming things" - Phil Karlton
- Edge cases multiply quickly
- Adds complexity without proportional benefit

---

## 2. Aggressive Fetch: ALL Records on Cache Miss

### Decision

**When cache misses, fetch ALL records from table (paginated at 1000/batch)**

### Rationale

**Problem:** Cache miss → Need data → How much to fetch?

**Options considered:**

**A) Fetch only requested records (limit + offset)** ❌
- Fast first query
- Minimal API usage
- **Cons:** Every query hits API, no cache benefit, defeats caching purpose

**B) Fetch requested + buffer (e.g., limit * 2)** ❌
- Some cache benefit
- Still fairly fast
- **Cons:** Arbitrary buffer size, may still hit API frequently

**C) Fetch ALL records** ✅ **CHOSEN**
- Maximize cache hit rate
- Enables local filtering/sorting
- One-time cost, then instant queries
- **Cons:** Slow first query, high initial memory

### Implementation

```ruby
def refresh_cache(table_id)
  # Fetch ALL records (paginated)
  all_records = []
  offset = 0

  loop do
    batch = api_list_records(table_id, limit: 1000, offset: offset)
    break if batch.empty?

    all_records.concat(batch)
    offset += batch.length
  end

  # Store in SQLite
  db.transaction do
    all_records.each { |record| insert_record(table_id, record) }
  end

  # Update metadata
  update_cache_metadata(table_id, all_records.length)
end
```

### Trade-offs

**Pros:**
- ✅ Maximizes cache hit rate (80%+)
- ✅ Enables unlimited local queries
- ✅ SQL filtering/sorting on cached data
- ✅ Subsequent queries instant (5-20ms)

**Cons:**
- ⚠️ First query slow (500-2000ms for 1000 records)
- ⚠️ Large tables (100K+ records) take longer (3-10 seconds)
- ⚠️ Memory spike during fetch

**Real-world impact:**

**Small table (100 records):**
- First query: 500ms (1 API call)
- Next 100 queries: 5-20ms each (0 API calls)
- Total time saved: 99+ seconds

**Large table (10,000 records):**
- First query: 3 seconds (10 API calls)
- Next 100 queries: 10-30ms each (0 API calls)
- Total time saved: 297 seconds

**Value proposition:** Pay upfront cost once, benefit for 4 hours

---

## 3. TOON Format Responses (Not JSON)

### Decision

**Return responses in TOON format (Token-Oriented Object Notation) for list operations**

### Rationale

**Problem:** Claude has token limits; minimize token usage

**Options considered:**

**A) Return JSON** ❌
```json
{
  "records": [
    {"id": "rec_123", "status": "Active", "priority": "High"},
    {"id": "rec_456", "status": "Done", "priority": "Low"}
  ]
}
```
~80 tokens per record (field names repeated)

**B) Return plain text** ❌
```
--- Record 1 ---
id: rec_123
status: Active
priority: High
```
~50 tokens per record (30-50% savings, but still verbose)

**C) Return TOON format** ✅ **CHOSEN**
```
records[2]{id|status|priority}:
rec_123|Active|High
rec_456|Done|Low
```
~30 tokens per record (50-60% savings vs JSON)

### Implementation

```ruby
# Using toon-ruby gem
def format_records(records, total_count:, filtered_count: nil)
  SmartSuite::Formatters::ToonFormatter.format_records(
    records,
    total_count: total_count,
    filtered_count: filtered_count
  )
end
```

### Trade-offs

**Pros:**
- ✅ 50-60% token savings vs JSON
- ✅ Tabular format eliminates repetitive field names
- ✅ Claude parses it accurately
- ✅ Compact but readable

**Cons:**
- ⚠️ Less human-readable than plain text
- ⚠️ Requires toon-ruby gem

**Why TOON works for SmartSuite:**
- Records are uniform (same fields per table)
- Tabular format ideal for structured data
- Field names appear once in header, not per record
- MCP protocol wraps result in JSON anyway

---

## 4. Required Fields Parameter (No Default "All Fields")

### Decision

**`list_records` requires `fields` parameter; no default to return all fields**

### Rationale

**Problem:** Returning all fields wastes tokens on unused data

**Options considered:**

**A) Default to all fields** ❌
- Convenient
- User doesn't need to specify
- **Cons:** Massive token waste, 10+ fields when 2-3 needed

**B) Return minimal default set** ❌
- Some token savings
- Still automatic
- **Cons:** Arbitrary choice, may not include needed fields

**C) Require explicit field selection** ✅ **CHOSEN**
- User controls exactly what they get
- Maximum token efficiency
- **Cons:** Requires knowing field names (mitigated by get_table)

### Implementation

```ruby
def list_records(table_id, limit, offset, fields:, ...)
  raise "fields parameter is required" if fields.nil? || fields.empty?

  # Only fetch/return specified fields
  query.select(fields)
end
```

### Trade-offs

**Pros:**
- ✅ 60-80% token savings (3 fields vs 15 fields)
- ✅ Forces user to think about what they need
- ✅ Faster queries (less data transfer)

**Cons:**
- ⚠️ Extra step: get table structure first
- ⚠️ Can't explore data without knowing fields

**Mitigation:**
- `get_table` shows available fields
- Claude can ask user what fields they want
- Error message explains requirement

**Example workflow:**
```
User: Show me tasks
Claude: What fields would you like to see?
User: Status and priority
Claude: [Uses list_records with fields: ['status', 'priority']]
```

---

## 5. Table Structure Filtering (83.8% Reduction)

### Decision

**Filter table structures to remove UI/display metadata, keeping only essential schema information**

### Rationale

**Problem:** SmartSuite API returns massive structures with UI config

**Full structure:** ~600-1200 tokens per table
**Filtered structure:** ~100-200 tokens per table

**What we keep:**
- ✅ `slug` (field identifier)
- ✅ `label` (human-readable name)
- ✅ `field_type` (type for queries)
- ✅ `required`, `unique`, `primary`
- ✅ `choices` (for select fields, simplified)
- ✅ `linked_application` (for linked records)

**What we remove:**
- ❌ Display formats, colors, icons
- ❌ Column widths, visibility settings
- ❌ Help text, validation rules (can request if needed)
- ❌ UI-only metadata
- ❌ Detailed params (keep minimal set)

### Implementation

```ruby
def filter_field_structure(structure)
  structure.map do |field|
    filtered = {
      slug: field[:slug],
      label: field[:label],
      field_type: field[:field_type]
    }

    # Conditionally include
    filtered[:required] = field[:required] if field[:required]
    filtered[:choices] = simplify_choices(field[:params][:choices]) if select_field?

    filtered
  end
end
```

### Trade-offs

**Pros:**
- ✅ 83.8% token savings on structure requests
- ✅ Easier to read and understand
- ✅ Focuses on essentials for queries

**Cons:**
- ⚠️ Can't see UI config without separate request
- ⚠️ Missing some field properties

**Mitigation:**
- User can request full structure if needed (not default)
- Essential fields always available

---

## 6. SQLite Over In-Memory or Redis

### Decision

**Use SQLite for caching, not in-memory (Ruby Hash) or Redis**

### Rationale

**Options considered:**

**A) In-memory (Ruby Hash)** ❌
```ruby
@cache = {}
@cache[table_id] = records
```
- Fast (RAM)
- Simple
- **Cons:** Lost on server restart, no persistence, no querying

**B) Redis** ❌
- Fast (RAM)
- Persistent
- Built-in TTL
- **Cons:** Requires separate server, complex setup, overkill for single-user

**C) SQLite** ✅ **CHOSEN**
- Persistent (survives restarts)
- No separate server
- SQL querying (filters, sorts, pagination)
- Single file deployment
- **Cons:** Slower than RAM (but still 5-20ms)

### Why SQLite Wins for This Use Case

**Persistence matters:**
- Server may restart (Claude Desktop restart, system reboot)
- Re-fetching 100,000 records takes minutes
- SQLite preserves cache across restarts

**SQL querying matters:**
- Filter cached data with WHERE clauses
- Sort cached data with ORDER BY
- Paginate with LIMIT/OFFSET
- No need to load all records into memory

**Single-file simplicity:**
- `~/.smartsuite_mcp_cache.db` - one file
- Easy to backup: `cp ~/.smartsuite_mcp_cache.db backup.db`
- Easy to clear: `rm ~/.smartsuite_mcp_cache.db`
- No configuration required

**Performance is "good enough":**
- 5-20ms response time vs 1000ms API call = 99% faster
- 10ms vs 1ms (Redis) is imperceptible to users
- Simplicity > marginal performance gain

### Trade-offs

**Pros:**
- ✅ Persistent across restarts
- ✅ SQL querying capabilities
- ✅ No separate server
- ✅ Single file deployment
- ✅ ACID transactions

**Cons:**
- ⚠️ Slower than Redis (5-20ms vs <1ms)
- ⚠️ Disk I/O (but SSDs are fast)

**Real-world impact:**
- SQLite: 10ms response
- Redis: 1ms response
- Difference: 9ms (imperceptible)
- Complexity savings: Massive

---

## 7. Session Tracking in Same Database

### Decision

**Store API statistics in same SQLite database as cache**

### Rationale

**Problem:** Need to track API usage across sessions

**Options considered:**

**A) Separate statistics database** ❌
- Clear separation of concerns
- **Cons:** Two files to manage, sync issues

**B) In-memory only (lost on restart)** ❌
- Simple
- **Cons:** No historical analysis

**C) Same database as cache** ✅ **CHOSEN**
- Single file
- Shared transactions
- Persistent
- **Cons:** Couples two concerns (acceptable trade-off)

### Implementation

```sql
-- Same database file: ~/.smartsuite_mcp_cache.db

-- Cache tables
CREATE TABLE cache_metadata (...);
CREATE TABLE cache_tbl_abc123 (...);

-- Stats tables (same DB)
CREATE TABLE api_calls (...);
CREATE TABLE api_stats_summary (...);
```

### Trade-offs

**Pros:**
- ✅ Single file to manage
- ✅ Atomic operations (same transaction)
- ✅ Easy backup (one file)
- ✅ Simplified deployment

**Cons:**
- ⚠️ Couples cache and stats
- ⚠️ Deleting cache also deletes stats

**Mitigation:**
- Separate `reset_api_stats` tool (doesn't delete cache)
- Logical separation (different tables)

---

## 8. No Automatic Cache Cleanup

### Decision

**Never automatically delete cache; user controls via manual deletion**

### Rationale

**Problem:** Cache grows over time; when to clean up?

**Options considered:**

**A) Auto-delete after X days** ❌
- Automatic management
- **Cons:** Arbitrary threshold, may delete useful data

**B) LRU eviction** ❌
- Keeps most-used data
- **Cons:** Complex, overhead, user surprise

**C) No automatic cleanup** ✅ **CHOSEN**
- User controls
- Cache provides value
- **Cons:** Can grow large

### Reasoning

**Cache is valuable:**
- Even old cache is better than no cache
- 1-year-old data still returns instantly vs 2-second API call
- User can query historical data without API hits

**Storage not constrained:**
- Typical workspace: 1-50 MB
- Large workspace: 100-500 MB
- Modern systems have GBs/TBs of storage

**User has control:**
```bash
# Check size
ls -lh ~/.smartsuite_mcp_cache.db

# Delete if needed
rm ~/.smartsuite_mcp_cache.db
```

### Trade-offs

**Pros:**
- ✅ Simple (no cleanup logic)
- ✅ User controls
- ✅ Old cache still useful

**Cons:**
- ⚠️ Can grow large (rare)
- ⚠️ User must manually delete

**Typical growth:**
- 10 tables × 1,000 records = 1-5 MB
- 50 tables × 10,000 records = 50-100 MB
- 100 tables × 100,000 records = 500 MB - 1 GB

---

## 9. Privacy-Preserving Stats (Hashed API Keys)

### Decision

**Hash API keys with SHA256 before storing in statistics**

### Rationale

**Problem:** Need to track usage per user, but API keys are sensitive

**Options considered:**

**A) Store raw API keys** ❌
- Simple
- **Cons:** Security risk, plaintext credentials

**B) Don't track per-user** ❌
- Most secure
- **Cons:** Can't analyze usage by user

**C) Hash API keys** ✅ **CHOSEN**
- Privacy-preserving
- Enables per-user tracking
- **Cons:** Can't reverse hash to identify user

### Implementation

```ruby
def track_api_call(solution_id:, table_id:, http_method:, endpoint:)
  user_hash = Digest::SHA256.hexdigest(ENV['SMARTSUITE_API_KEY'])[0..7]

  db.execute(<<~SQL, [session_id, user_hash, ...])
    INSERT INTO api_calls (session_id, user_hash, ...)
    VALUES (?, ?, ...)
  SQL
end
```

**Result:** `user_hash = "a1b2c3d4"` (first 8 chars of SHA256)

### Trade-offs

**Pros:**
- ✅ Privacy-preserving (can't extract API key)
- ✅ Enables per-user aggregation
- ✅ Collision-resistant (8 chars = 4 billion possibilities)

**Cons:**
- ⚠️ Can't identify user from hash (by design)

**Use cases enabled:**
- Compare usage across different API keys
- Detect unusual patterns
- Aggregate by user without exposing credentials

---

## 10. Table-Based TTL (Not Per-Record)

### Decision

**All records in a table expire together (table-based TTL), not individually**

### Rationale

**Problem:** When should cached records expire?

**Options considered:**

**A) Per-record TTL** ❌
```sql
SELECT * FROM cache_table WHERE _expires_at > NOW()
```
- Granular control
- **Cons:** Overhead per record, complex queries, partial table caching

**B) Table-based TTL** ✅ **CHOSEN**
```sql
SELECT expires_at FROM cache_metadata WHERE table_id = ?
```
- Simple check
- All-or-nothing
- **Cons:** All records refresh together (even if some still fresh)

### Reasoning

**Simplicity:**
- One metadata row per table
- Single expiration check
- Clear cache state (valid or invalid)

**Efficiency:**
- No per-record overhead
- Fast validity check (single query)
- Batch operations (refresh all or none)

**Practicality:**
- Records in a table usually change together
- User cares about table freshness, not individual records
- Easier to reason about

### Implementation

```ruby
def cache_valid?(table_id)
  row = db.execute(<<~SQL, [table_id])
    SELECT expires_at FROM cache_metadata WHERE table_id = ?
  SQL

  return false if row.empty?

  expires_at = DateTime.parse(row[0]['expires_at'])
  DateTime.now < expires_at
end
```

### Trade-offs

**Pros:**
- ✅ Simple implementation
- ✅ Fast validity check
- ✅ Clear semantics (table valid or not)
- ✅ No per-record overhead

**Cons:**
- ⚠️ All records refreshed even if some still fresh
- ⚠️ Can't have different TTLs per record

**Acceptable because:**
- Records in a table change at similar rates
- Batch refresh is efficient (one transaction)
- User rarely needs per-record TTL control

---

## 11. Minimal Dependencies (Essential Gems Only)

### Decision

**Use Ruby standard library plus minimal essential gems**

### Rationale

**Problem:** Need HTTP client, JSON parsing, SQLite caching, token-optimized output

**Options considered:**

**A) Use many popular gems** ❌
- Faraday (HTTP)
- ActiveRecord (ORM)
- Many formatting/utility gems
- **Cons:** Heavy dependencies, version conflicts, installation complexity

**B) Standard library only** ❌
- No external dependencies
- **Cons:** Would require reimplementing SQLite bindings and TOON format

**C) Minimal essential gems** ✅ **CHOSEN**
- Standard library for HTTP (`net/http`), JSON, etc.
- `sqlite3` gem for caching (required - no stdlib SQLite)
- `toon-ruby` gem for TOON format (50-60% token savings)
- **Cons:** Requires `bundle install`, but minimal maintenance

### Current Dependencies

**Production gems:**
- `sqlite3` - SQLite database bindings (caching layer)
- `toon-ruby` - TOON format encoding (token optimization)

**Development/test gems:**
- `minitest`, `rake` - Testing
- `rubocop`, `reek` - Code quality
- `yard` - Documentation
- `simplecov` - Coverage
- `bundler-audit` - Security

### Reasoning

**Simplicity maintained:**
- Only 2 production gems
- Both are stable, well-maintained libraries
- Clear purpose for each (caching, token optimization)

**Reliability:**
- `sqlite3` is mature (20+ years)
- `toon-ruby` is purpose-built for this use case
- No breaking changes expected

**Deployment:**
- `bundle install` is standard Ruby workflow
- Installation scripts handle dependencies automatically
- Works on macOS, Linux, Windows

### Trade-offs

**Pros:**
- ✅ Minimal dependencies (2 production gems)
- ✅ Simple deployment (`bundle install`)
- ✅ Stable, well-maintained gems
- ✅ Essential functionality only (SQLite, TOON)

**Cons:**
- ⚠️ Requires Bundler setup
- ⚠️ Gem updates needed occasionally

**Why these specific gems:**

**sqlite3:**
- No stdlib SQLite bindings in Ruby
- Essential for caching strategy
- C extension = fast performance

**toon-ruby:**
- 50-60% token savings vs JSON
- Purpose-built for AI/LLM contexts
- Simple API, zero configuration

---

## 12. Stdin/Stdout vs HTTP Server

### Decision

**Communicate via stdin/stdout (MCP protocol), not HTTP**

### Rationale

**Dictated by MCP protocol:**
- Claude Desktop expects stdin/stdout communication
- JSON-RPC 2.0 over stdio
- No choice here (protocol requirement)

**Benefits:**
- Simple process model (one process per Claude instance)
- No port management
- No network configuration
- Direct integration with Claude Desktop

**Alternative (if not using MCP):**
- HTTP server (e.g., Sinatra, Rails)
- Would require: port, server, networking
- MCP is better fit for AI assistant integration

---

## Future Considerations

### Potential Changes

**1. Smart TTL per table:**
- Track update frequency
- Adjust TTL dynamically
- Frequently updated tables: shorter TTL
- Rarely updated tables: longer TTL

**2. Partial cache updates:**
- Fetch only changed records
- Use `last_updated` field
- Reduce refresh time for large tables

**3. Background cache refresh:**
- Refresh before expiry
- User never sees slow query
- Requires background job scheduler

**4. Compression for large fields:**
- Compress long text fields
- Reduces cache size
- Trade-off: CPU for disk space

### Why Not Now?

**Premature optimization:**
- Current design works well
- Complexity not justified yet
- Can add incrementally if needed

**YAGNI principle:**
- "You Aren't Gonna Need It"
- Build what's needed today
- Extend when proven necessary

---

## Summary of Key Principles

1. **Simplicity over perfection** - Simple solutions that work beat complex optimal solutions
2. **User control** - Give user control (bypass cache, select fields, etc.)
3. **Good enough performance** - 99% faster is enough; don't optimize the last 1%
4. **Minimal dependencies** - Essential gems only (sqlite3, toon-ruby); easier deployment and maintenance
5. **Privacy-preserving** - Hash sensitive data; track usage without exposing credentials
6. **Predictable behavior** - TTL-based expiration; clear semantics
7. **Token efficiency** - TOON format, filtered structures, required fields
8. **Fail gracefully** - Errors propagate clearly; user gets helpful messages

---

## Related Documentation

- **[Architecture Overview](overview.md)** - System architecture
- **[Caching System](caching-system.md)** - Cache implementation
- **[MCP Protocol](mcp-protocol.md)** - Protocol details
- **[Performance Guide](../guides/performance-guide.md)** - Optimization strategies

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
