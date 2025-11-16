# v1.6 Roadmap Decisions

**Purpose:** Decision log for v1.6 high priority items
**Status:** Draft - awaiting decisions
**Last Updated:** November 15, 2025

---

## Instructions

For each item below:

1. Read the questions and my recommendation
2. Fill in **YOUR DECISION** section
3. Add notes/modifications as needed
4. Mark status: ⏳ Pending | ✅ Approved | 🔄 Modified | ❌ Rejected | 🤔 Need Research

---

## Item 1: Rename `cached_table_schemas` → `cache_table_registry`

**Status:** ⏳ Pending

### Context

Currently have two confusingly-named tables:

- `cached_table_schemas` - Internal registry of dynamic SQL cache tables we create
- `cached_tables` - Cached table list from SmartSuite API

### Questions

**Q1:** Proceed with renaming to `cache_table_registry`?

**My Recommendation:** ✅ **Yes, rename it**

- Much clearer purpose
- Reduces onboarding confusion
- Standard naming pattern: `cache_*` for API caches, `cache_table_*` for internal metadata

**Q2:** Alternative names to consider?

**My Recommendation:** Consider these options:

1. `cache_table_registry` (my top choice - clear and concise)
2. `_cache_internal_tables` (underscore = internal, but less discoverable)
3. `dynamic_cache_tables` (descriptive but verbose)

**Q3:** When to remove migration code for old schema?

**My Recommendation:** Remove in **v2.0**

- Keep migration through v1.x series (v1.6, v1.7, etc.)
- Gives users ~6 months to upgrade
- Document in v1.9 release notes: "Last version with automatic migration"

---

### YOUR DECISION

**Approve recommendation?** [ ] Yes [ ] No [ ] Modified

**Preferred name:** cache_table_registry

**Migration removal timeline:** 1.6

**Notes:**
I am the only user of this software, so no need to consider other users.

---

## Item 2: Review Current Cache Layer Schema

**Status:** ⏳ Pending

### Context

Current schema has 9 metadata tables. Is this over-engineered?

**Current tables:**

- `cache_table_registry` (metadata for dynamic tables)
- `cache_ttl_config` (TTL settings per table)
- `cache_stats` (operation statistics)
- `api_call_log` (API call history)
- `api_stats_summary` (API usage summary)
- `cached_solutions` (solutions list cache)
- `cached_tables` (tables list cache)
- Plus 1 dynamic table per SmartSuite table (e.g., `cache_records_tbl_123`)

### Questions

**Q1:** Which tables feel redundant or could be merged?

**My Recommendation:** **Keep current structure, but consider merging in v2.0:**

**Keep as-is (all serve distinct purposes):**

- `cache_table_registry` - Essential for dynamic table management
- `cached_solutions` - Frequently accessed, good separation
- `cached_tables` - Frequently accessed, good separation
- Dynamic `cache_records_*` tables - Core caching mechanism

**Consider merging later (v2.0):**

- `cache_stats` + `cache_ttl_config` → `cache_metadata` (combines stats and config)
- `api_call_log` + `api_stats_summary` → Keep separate (one is raw log, one is aggregation)

**Rationale:** Current schema is NOT over-engineered - each table serves a purpose. Premature consolidation would reduce flexibility.

**Q2:** Are there missing indexes causing slow queries?

**My Recommendation:** **Add these indexes (if they don't exist):**

```sql
CREATE INDEX IF NOT EXISTS idx_cache_stats_category_timestamp
  ON cache_stats(category, timestamp);

CREATE INDEX IF NOT EXISTS idx_api_call_log_table_timestamp
  ON api_call_log(table_id, timestamp);
```

**Test with:** Run `EXPLAIN QUERY PLAN` on common queries to verify index usage.

**Q3:** Should we normalize or denormalize further?

**My Recommendation:** **Current balance is good**

- Denormalized caches (`cached_solutions`, `cached_tables`) = Fast reads ✅
- Normalized metadata (`cache_table_registry`) = Flexibility ✅
- No changes needed

---

### YOUR DECISION

**Schema changes approved?** [x] Yes [ ] No [ ] Modified

**Tables to merge/split:** Keep as is

**Indexes to add:** none

**Timeline:** [x] v1.6 [ ] v2.0 [ ] Defer

**Notes:**

---

## Item 3: Analyze list_records vs get_records Response

**Status:** ⏳ Pending

### Context

Need to verify that `POST /applications/{id}/records/list/` returns complete field data, so we don't need individual `GET /applications/{id}/records/{record_id}` calls.

### Questions

**Q1:** Which endpoint currently populates cache?

**My Recommendation:** **Investigate current implementation**

Check `lib/smartsuite/api/record_operations.rb` to see:

- Does `list_records` use `?hydrated=true`?
- Does response include all field values?
- Or are some fields truncated/omitted?

**Q2:** Does list_records return full field data?

**My Recommendation:** **Test with actual API call**

Run this test:

```ruby
# In SmartSuite API
response = client.list_records('table_id', 1, hydrated: true)
record_from_list = response['items'][0]

record_from_get = client.get_record('table_id', record_id)

# Compare field counts
puts "List fields: #{record_from_list.keys.count}"
puts "Get fields: #{record_from_get.keys.count}"
puts "Missing: #{(record_from_get.keys - record_from_list.keys)}"
```

**Expected result:** They should be identical with `hydrated=true`

**Q3:** If list_records is sufficient, update caching strategy?

**My Recommendation:** **YES - Use list_records exclusively**

**Benefits:**

- Fewer API calls (1 paginated call vs 1 + N individual calls)
- Faster cache population
- Lower API rate limit usage
- Simpler code

**Implementation:**

- Verify `list_records` uses `hydrated=true` parameter
- Document that cache population uses list endpoint
- Remove any individual `get_record` calls during cache population

---

### YOUR DECISION

**Action:** [x] Test API first [ ] Assume list_records is sufficient [ ] Keep current approach

**Findings from test:** list_records with hydrated=true returns full data. The only field not returned is deleted_by field, which is acceptable.

**Approved change?** [x] Yes [ ] No [ ] Need more testing

**Notes:**

---

## Item 4: Improve Dynamic Table and Column Naming

**Status:** ⏳ Pending

### Context

**Current naming:**

- SQL table: `cache_records_{sanitized_table_id}` (e.g., `cache_records_tbl_abc123`)
- Columns: Sanitized field slugs (e.g., `s7e8c12e98` or `f_s7e8c12e98`)

**Problems:**

- Column names are opaque hashes, hard to debug
- SQL queries are unreadable: `SELECT s7e8c12e98 FROM cache_records_tbl_abc123`

### Questions

**Q1:** Include human-readable table names in SQL table names?

**My Recommendation:** **YES - Include both name and ID**

**Proposed format:**

```
cache_records_{sanitized_name}_{table_id}
```

**Examples:**

- Current: `cache_records_tbl_abc123`
- Proposed: `cache_records_customers_tbl_abc123`

**Benefits:**

- Instantly recognize what table you're looking at
- Easier debugging with SQLite browser
- SQL queries more readable

**Handling collisions:**

- If same name exists, append number: `cache_records_projects_2_tbl_def456`
- Use table_id as ultimate uniqueness guarantee

**Q2:** Use field labels instead of slugs for column names?

**My Recommendation:** **YES, with fallback to slug**

**Strategy:**

```ruby
def column_name(field)
  # Try label first (sanitized)
  label = sanitize_column_name(field['label'])

  # If label conflicts with reserved word or existing column, use slug
  if conflicts?(label)
    sanitize_column_name(field['slug'])
  else
    label
  end
end
```

**Examples:**

- Field label "Status" → column `status`
- Field label "Email Address" → column `email_address`
- Field slug `s7e8c12e98` → column `s7e8c12e98` (fallback if label conflicts)

**Benefits:**

- Readable SQL: `SELECT status, email_address FROM cache_records_customers`
- Debug queries make sense
- Easier for developers to work with

**Risks & Mitigations:**

- **Risk:** Label changes break queries
  - **Mitigation:** Store mapping in `cache_table_registry`, use slug as stable identifier
- **Risk:** Labels might have SQL reserved words
  - **Mitigation:** Prefix with `field_` if reserved (e.g., `field_order`)
- **Risk:** Migration needed for existing caches
  - **Mitigation:** Just invalidate cache, will rebuild with new names

**Q3:** Add type prefixes to columns (e.g., `date_created`, `num_amount`)?

**My Recommendation:** **NO - Keep names clean**

Type prefixes make names verbose and redundant (SQLite already knows column types).

**Exception:** Multi-column fields already use suffixes:

- `due_date_from`, `due_date_to` (date range)
- `address_text`, `address_json` (address field)

This is good - keep this pattern.

---

### YOUR DECISION

**Include table names in SQL table names?** [x] Yes [ ] No

**Use field labels for columns?** [ ] Yes [ ] No [x] Labels with slug fallback

**Require migration?** [ ] Yes - rebuild all caches [x] No - apply to new caches only

**Timeline:** [x] v1.6 [ ] v1.7 [ ] v2.0

**Notes:**

---

## Item 5: Increase Cache TTL to 1 Week

**Status:** ⏳ Pending

### Context

**Current TTLs:**

- Solutions: 24 hours
- Tables: 12 hours
- Records: 4 hours (configurable)

**Rationale for increase:**

- Solutions rarely change (new solutions added infrequently)
- Table structures rarely change (fields added occasionally)
- 1 week TTL reduces API calls significantly

### Questions

**Q1:** What TTLs for each resource type?

**My Recommendation:**

| Resource        | Current | Proposed   | Reasoning                                              |
| --------------- | ------- | ---------- | ------------------------------------------------------ |
| Solutions list  | 24h     | **7 days** | Very stable, changes are rare                          |
| Table list      | 12h     | **7 days** | Table creation is infrequent                           |
| Table structure | 12h     | **7 days** | Field additions are rare events                        |
| Records         | 4h      | **12h**    | Keep current - data changes frequently                 |
| Members         | N/A     | **7 days** | Team membership that I work with, changes infrequently |

**Q2:** Should TTL be configurable or hardcoded?

**My Recommendation:** **Hardcoded with sane defaults, configurable in v2.0**

**v1.6 approach (simple):**

```ruby
# In cache_layer.rb
SOLUTION_TTL = 7 * 24 * 3600  # 7 days
TABLE_TTL = 7 * 24 * 3600     # 7 days
RECORD_TTL = 12 * 3600         # 12 hours (configurable per table)
```

**v2.0 approach (advanced):**

- Add configuration file: `~/.smartsuite_mcp_config.yml`
- Allow users to override TTLs
- Provide presets: `aggressive`, `balanced`, `conservative`

**Q3:** How to handle edge case where structure changes?

**My Recommendation:** **Explicit invalidation on structure changes**

**Trigger invalidation when:**

1. User calls `add_field`, `update_field`, `delete_field`
2. User calls `create_table`

**Implementation:**

```ruby
# In field_operations.rb
def add_field(table_id, field_data)
  result = api_request(:post, "/applications/#{table_id}/add_field/", body: {...})

  # Invalidate table structure cache
  @cache.invalidate_table_list_cache(nil)  # All tables
  @cache.invalidate_table_cache(table_id)  # This specific table

  result
end
```

**Benefits:**

- Long TTL for normal operations (fewer API calls)
- Immediate freshness when structure actually changes
- Best of both worlds

**Q4:** Add user-visible cache status indicator?

**My Recommendation:** **YES - Add to tool registry**

Add new tool: `get_cache_status`

**Returns:**

```json
{
  "solutions": {
    "status": "valid",
    "cached_at": "2025-11-10T10:00:00Z",
    "expires_at": "2025-11-17T10:00:00Z",
    "time_remaining": "6 days 12 hours"
  },
  "tables": {
    "status": "valid",
    "cached_at": "2025-11-10T10:00:00Z",
    "expires_at": "2025-11-17T10:00:00Z"
  },
  "records": {
    "tbl_abc123": {
      "status": "valid",
      "record_count": 1500,
      "expires_at": "2025-11-10T14:00:00Z"
    }
  }
}
```

---

### YOUR DECISION

**Proposed TTLs approved?** [x] Yes [ ] No [ ] Modified

**Custom TTLs:**

- Solutions: \***\*\_\_\_\*\***
- Tables: \***\*\_\_\_\*\***
- Records: \***\*\_\_\_\*\***

**Add explicit invalidation on structure changes?** [x] Yes [ ] No

**Add get_cache_status tool?** [x] Yes [ ] No [ ] Later

**Timeline:** [x] v1.6 [ ] v1.7

**Notes:**

---

## Item 6: User-Triggered Cache Refresh

**Status:** ⏳ Pending

### Context

Allow users to manually refresh cache when they know data is stale.

### Questions

**Q1:** What interface(s) should we provide?

**My Recommendation:** **Start with MCP tool, add CLI in v2.0**

**Phase 1 (v1.6): MCP Tool**

```json
{
  "name": "refresh_cache",
  "description": "Manually refresh cached data",
  "parameters": {
    "type": "object",
    "properties": {
      "resource": {
        "type": "string",
        "enum": ["solutions", "tables", "records", "all"],
        "description": "What to refresh"
      },
      "table_id": {
        "type": "string",
        "description": "Required if resource='records'"
      },
      "solution_id": {
        "type": "string",
        "description": "Optional: limit to specific solution"
      }
    },
    "required": ["resource"]
  }
}
```

**Examples:**

```javascript
// Refresh solutions list
refresh_cache({ resource: 'solutions' })

// Refresh specific table's records
refresh_cache({ resource: 'records', table_id: 'tbl_123' })

// Refresh all tables in a solution
refresh_cache({ resource: 'tables', solution_id: 'sol_456' })

// Refresh everything
refresh_cache({ resource: 'all' })
```

**Phase 2 (v2.0): CLI Tool**

```bash
# Future enhancement
ruby scripts/cache_manager.rb refresh --table tbl_123
ruby scripts/cache_manager.rb refresh --all
ruby scripts/cache_manager.rb stats
```

**Q2:** What should "refresh" do?

**My Recommendation:** **Invalidate + immediate refetch**

**Behavior:**

```ruby
def refresh_cache(resource:, table_id: nil, solution_id: nil)
  case resource
  when 'solutions'
    @cache.invalidate_solutions_cache
    fetch_and_cache_solutions  # Immediate refetch

  when 'tables'
    @cache.invalidate_table_list_cache(solution_id)
    fetch_and_cache_tables(solution_id)

  when 'records'
    @cache.invalidate_table_cache(table_id)
    # Don't refetch immediately - too expensive
    # Will refetch on next list_records call

  when 'all'
    # Invalidate everything, let refetch happen on demand
    invalidate_all_caches
  end

  {status: "success", message: "Cache refreshed"}
end
```

**Q3:** Should refresh be synchronous or async?

**My Recommendation:** **Synchronous for metadata, async for records**

| Resource  | Approach | Reason                                      |
| --------- | -------- | ------------------------------------------- |
| Solutions | Sync     | Fast (<1s), immediate freshness             |
| Tables    | Sync     | Fast (<2s), immediate freshness             |
| Records   | Async    | Slow (could be minutes), return immediately |
| All       | Async    | Very slow, background job                   |

**Implementation:**

```ruby
# Sync example
refresh_cache(resource: 'solutions')
# Returns: {status: "success", cached: 110, duration: 0.8}

# Async example
refresh_cache(resource: 'records', table_id: 'tbl_123')
# Returns: {status: "invalidated", message: "Will refresh on next access"}
```

**Q4:** Track refresh history?

**My Recommendation:** **YES - Log to cache_stats**

Add to `cache_stats` table:

```ruby
record_stat('manual_refresh', resource, key, {
  user: user_hash,
  timestamp: Time.now.to_i,
  records_affected: count
})
```

Helps understand:

- How often users need manual refresh (indicates TTL might be wrong)
- Which resources need refresh most often
- User behavior patterns

---

### YOUR DECISION

**Interface:** [ ] MCP tool only [ ] CLI only [x] Both

**Refresh behavior:** [x] Invalidate only [ ] Invalidate + refetch [ ] Custom: \***\*\_\_\_\*\***

**Async for expensive operations?** [x] Yes [ ] No

**Track refresh history?** [x] Yes [ ] No

**Timeline:** [x] v1.6 [ ] v1.7

**Notes:**
I would like to configure the tables that I frequently use so that I can trigger refreshes on them.

---

## Item 7: Remove Old Cache Format Migration Code

**Status:** ⏳ Pending

### Context

Lines 178-247 in `cache_layer.rb` handle migration from old schemas:

- Old `data` column → new fixed columns
- INTEGER timestamps → TEXT timestamps (ISO 8601)
- Drops obsolete tables: `cached_table_lists`, `cached_all_tables`

### Questions

**Q1:** When to remove migration code?

**My Recommendation:** **Remove in v2.0 (Q1 2026)**

**Timeline:**

- **v1.6 (Dec 2025):** Keep migration, add deprecation warning
- **v1.7-v1.9 (Jan-Mar 2026):** Keep migration, warn in logs
- **v2.0 (Apr 2026):** Remove migration code

**Deprecation warning (add in v1.6):**

```ruby
def migrate_cache_tables_schema
  if has_old_solutions_schema || has_old_tables_schema
    warn "=" * 80
    warn "DEPRECATION WARNING: Old cache schema detected"
    warn "Automatically migrating to new schema..."
    warn "This automatic migration will be removed in v2.0"
    warn "If you see this message, you're upgrading from pre-v1.5"
    warn "=" * 80

    # ... migration code ...
  end
end
```

**Q2:** What happens to users on very old versions?

**My Recommendation:** **Document upgrade path, cache rebuild is acceptable**

**Scenario:** User upgrades from v1.4 → v2.0 (skipping v1.5-v1.9)

**Result:** Cache is dropped and rebuilt

- Loss: None (it's just a cache)
- Impact: First queries after upgrade will be slower (cache miss)
- Acceptable: Yes, caches are meant to be disposable

**Documentation (add to CHANGELOG):**

```markdown
## v2.0 Breaking Changes

### Cache Schema Migration Removed

Automatic migration from pre-v1.5 cache schemas has been removed.

**Impact:** If upgrading from v1.4 or earlier, your cache will be
rebuilt on first use.

**Action Required:** None - cache rebuilds automatically.
**Workaround:** If upgrading from v1.4, upgrade to v1.9 first, then v2.0.
```

**Q3:** Complexity reduction - how many lines removed?

**My Recommendation:** **Estimate 60-70 lines removed**

**Code to remove in v2.0:**

- `migrate_cache_tables_schema` method (60 lines)
- `migrate_api_call_log_schema` method (10 lines)
- Old table drop statements

**Net benefit:**

- Simpler codebase
- Faster initialization
- Less maintenance burden

---

### YOUR DECISION

**Removal timeline approved?** [ ] Yes [ ] No [x] Modified: Remove now, there aren't any users of this software other than myself.

**Add deprecation warning in v1.6?** [ ] Yes [x] No

**Document in CHANGELOG?** [x] Yes [ ] No

**Notes:**
Just remove it now, there aren't any users of this software other than myself.

---

## Item 8: Add Cache Metadata Table

**Status:** ⏳ Pending

### Context

Need visibility into cache performance: hit/miss ratios, table sizes, access patterns.

### Questions

**Q1:** New table or extend existing `cache_stats`?

**My Recommendation:** **Create new focused table: `cache_performance`**

**Why not extend `cache_stats`?**

- `cache_stats` is append-only log (grows forever)
- Need aggregated metrics, not raw events
- Separate concerns: stats=history, performance=current state

**Proposed schema:**

```sql
CREATE TABLE cache_performance (
  table_id TEXT PRIMARY KEY,
  table_name TEXT,

  -- Access metrics
  hit_count INTEGER DEFAULT 0,
  miss_count INTEGER DEFAULT 0,
  last_access_time TEXT,

  -- Size metrics
  record_count INTEGER DEFAULT 0,
  cache_size_bytes INTEGER,

  -- Efficiency metrics
  api_calls_saved INTEGER DEFAULT 0,
  tokens_saved INTEGER DEFAULT 0,

  -- Timestamps
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX idx_cache_perf_last_access
  ON cache_performance(last_access_time);
```

**Q2:** Track on every access or batch updates?

**My Recommendation:** **In-memory counters, periodic flush**

**Performance-sensitive approach:**

```ruby
class CacheLayer
  def initialize
    @perf_counters = {}  # In-memory: {table_id => {hits: 0, misses: 0}}
    @last_flush = Time.now
  end

  def cache_hit(table_id)
    @perf_counters[table_id] ||= {hits: 0, misses: 0}
    @perf_counters[table_id][:hits] += 1

    # Flush every 100 operations or 5 minutes
    flush_perf_counters if should_flush?
  end

  def flush_perf_counters
    @perf_counters.each do |table_id, counters|
      @db.execute(
        "INSERT INTO cache_performance (table_id, hit_count, miss_count, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(table_id) DO UPDATE SET
           hit_count = hit_count + excluded.hit_count,
           miss_count = miss_count + excluded.miss_count,
           updated_at = excluded.updated_at",
        [table_id, counters[:hits], counters[:misses], Time.now.utc.iso8601]
      )
    end
    @perf_counters.clear
    @last_flush = Time.now
  end

  def should_flush?
    total_ops = @perf_counters.values.sum { |c| c[:hits] + c[:misses] }
    total_ops >= 100 || (Time.now - @last_flush) > 300  # 100 ops or 5 min
  end
end
```

**Benefits:**

- Zero write overhead on hot path
- Batched writes are efficient
- Accurate metrics without performance penalty

**Q3:** What to track?

**My Recommendation:** **Start simple, expand later**

**v1.6 (core metrics):**

- ✅ Hit/miss counts
- ✅ Last access time
- ✅ Record count
- ✅ Cache size

**v1.7 (derived metrics):**

- Hit rate % (calculated from hits/misses)
- API calls avoided (based on hit count)
- Estimated token savings (hits × avg response size)

**v2.0 (advanced metrics):**

- Query latency percentiles (p50, p95, p99)
- Cache efficiency score
- Staleness indicators

**Q4:** Who consumes this data?

**My Recommendation:** **Make available via MCP tool**

**New tool: `get_cache_performance`**

```json
{
  "overall": {
    "total_hits": 1250,
    "total_misses": 150,
    "hit_rate": 0.893,
    "api_calls_saved": 1250,
    "tokens_saved_estimate": 875000
  },
  "by_table": [
    {
      "table_id": "tbl_abc123",
      "table_name": "Customers",
      "hit_count": 450,
      "miss_count": 50,
      "hit_rate": 0.9,
      "record_count": 1500,
      "cache_size_mb": 2.3,
      "last_access": "2025-11-15T14:30:00Z"
    }
  ],
  "least_used": [
    {
      "table_id": "tbl_xyz789",
      "table_name": "Archive",
      "hit_count": 1,
      "last_access": "2025-11-01T08:00:00Z"
    }
  ]
}
```

**Use cases:**

- Users check cache effectiveness
- Identify tables worth caching vs not
- Debug performance issues
- Optimize cache strategy

---

### YOUR DECISION

**Table name:** [x] cache_performance [ ] cache_metadata [ ] Other: \***\*\_\_\_\*\***

**Tracking approach:** [ ] Per-access DB write [x] In-memory + batch flush [ ] Other: \***\*\_\_\_\*\***

**Metrics to track (v1.6):**

- [x] Hit/miss counts
- [x] Last access time
- [x] Record counts
- [x] Cache size
- [ ] Other: \***\*\_\_\_\*\***

**Add MCP tool?** [x] Yes [ ] No [ ] Later

**Timeline:** [x] v1.6 [ ] v1.7

**Notes:**

---

## Item 9: Improve Prompt and Tool Registry

**Status:** ⏳ Pending

### Context

**Current state:**

- 26 tools in ToolRegistry
- 8 prompts in PromptRegistry
- Good foundation, but could be clearer

### Questions

**Q1:** What specific improvements?

**My Recommendation:** **Focus on better categorization and examples**

**Current issues:**

1. Tools not grouped logically (all in flat list)
2. Descriptions could be more prescriptive
3. Missing common-case examples
4. No guidance on tool combinations

**Proposed improvements:**

**A) Better tool categorization:**

```ruby
# In tool_registry.rb
def list_tools
  {
    "workspace_management": [
      {name: "list_solutions", category: "workspace", ...},
      {name: "analyze_solution_usage", category: "workspace", ...}
    ],
    "table_operations": [
      {name: "list_tables", category: "table", ...},
      {name: "get_table", category: "table", ...}
    ],
    # ... etc
  }
end
```

**B) Enhanced descriptions:**

```ruby
# Before (vague)
"description": "List records from a table"

# After (prescriptive)
"description": "List records from a table. IMPORTANT: Call get_table first to see available fields. Always specify 'fields' parameter to control token usage. Use cache for repeated queries."
```

**C) Add usage hints:**

```ruby
{
  "name": "list_records",
  "description": "...",
  "usage_hints": [
    "Always call get_table first to discover field slugs",
    "Specify minimal 'fields' array to reduce tokens",
    "Use bypass_cache: true after mutations",
    "Default limit is 10 - increase for larger datasets"
  ],
  "common_patterns": [
    "Basic query: {table_id, fields: ['status', 'title']}",
    "With filter: {table_id, fields: [...], filter: {...}}",
    "Fresh data: {table_id, fields: [...], bypass_cache: true}"
  ]
}
```

**Q2:** More filter examples in PromptRegistry?

**My Recommendation:** **Add 4 more common patterns**

**Current prompts (8):**

1. filter_active_records
2. filter_by_date_range
3. list_tables_by_solution
4. filter_records_contains_text
5. filter_by_linked_record
6. filter_by_numeric_range
7. filter_by_multiple_select
8. filter_by_assigned_user

**Add these (new):** 9. **filter_by_empty_field** - Common: "Find records where field is empty" 10. **filter_records_updated_recently** - Using last_updated field 11. **filter_multi_condition_and** - Complex AND conditions 12. **filter_multi_condition_or** - Complex OR conditions

**Example new prompt:**

```ruby
{
  name: "filter_by_empty_field",
  description: "Find records where a specific field is empty/null",
  arguments: [{name: "table_name", required: false}],
  template: <<~PROMPT
    Find all records in {{table_name}} where a field is empty:

    Example filter for empty email field:
    {
      "operator": "and",
      "fields": [
        {
          "field": "email",
          "comparison": "is_empty",
          "value": null
        }
      ]
    }

    Note: Use "is_empty" comparison, value can be null or omitted.
  PROMPT
}
```

**Q3:** Add anti-patterns documentation?

**My Recommendation:** **YES - Show what NOT to do**

**Add to ToolRegistry:**

```ruby
{
  "name": "list_records",
  "common_mistakes": [
    {
      "mistake": "Not specifying 'fields' parameter",
      "why_bad": "Returns ALL fields, wastes tokens",
      "fix": "Always specify: fields: ['field1', 'field2']"
    },
    {
      "mistake": "Using get_record in a loop",
      "why_bad": "N API calls instead of 1",
      "fix": "Use list_records with filter instead"
    },
    {
      "mistake": "Not using cache for repeated queries",
      "why_bad": "Unnecessary API calls",
      "fix": "Cache is automatic - just call list_records again"
    }
  ]
}
```

---

### YOUR DECISION

**Improvements approved?**

- [x] Better categorization
- [x] Enhanced descriptions
- [x] Usage hints
- [x] More filter examples (which ones?): \***\*\_\_\_\*\***
- [x] Anti-patterns documentation

**Priority:** [x] High [ ] Medium [ ] Low

**Timeline:** [x] v1.6 [ ] v1.7

**Notes:**

---

## Item 10: Implement Cache Warming Strategies

**Status:** ⏳ Pending

### Context

Pre-load frequently-accessed data to avoid cache misses.

### Questions

**Q1:** When to warm cache?

**My Recommendation:** **Manual trigger only (v1.6), automatic later (v2.0)**

**Why manual first?**

- Simple to implement
- User controls when warming happens
- No performance surprises
- Learn which tables users actually want warmed

**v1.6 approach:**

```ruby
# New tool: warm_cache
{
  "name": "warm_cache",
  "description": "Pre-load cache for frequently accessed tables",
  "parameters": {
    "tables": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Table IDs to warm, or 'auto' for top 5 most accessed"
    }
  }
}
```

**Usage:**

```javascript
// Warm specific tables
warm_cache({ tables: ['tbl_123', 'tbl_456'] })

// Auto-warm top 5
warm_cache({ tables: ['auto'] })
```

**v2.0 approach (automatic):**

- Warm on server startup
- Warm based on usage patterns
- Scheduled warming (nightly)

**Q2:** What to warm?

**My Recommendation:** **Warm based on access frequency**

**Strategy:**

```ruby
def get_tables_to_warm(strategy)
  case strategy
  when 'auto'
    # Top 5 most accessed tables from cache_performance
    db.execute(
      "SELECT table_id FROM cache_performance
       ORDER BY hit_count + miss_count DESC
       LIMIT 5"
    ).map { |r| r['table_id'] }

  when 'solution'
    # All tables in a solution (good for workspace switch)
    list_tables(solution_id: solution_id)

  when 'critical'
    # User-defined critical tables (future: config file)
    ['tbl_123', 'tbl_456']  # From config
  end
end
```

**Q3:** Warming performance/UI?

**My Recommendation:** **Show progress, run in background**

**Implementation:**

```ruby
def warm_cache(table_ids:)
  total = table_ids.size
  warmed = []
  errors = []

  table_ids.each_with_index do |table_id, i|
    begin
      # Fetch structure
      structure = get_table(table_id)

      # Fetch all records
      records = fetch_all_records(table_id)

      # Cache them
      @cache.cache_table_records(table_id, structure, records)

      warmed << {
        table_id: table_id,
        table_name: structure['name'],
        record_count: records.size
      }

      # Progress
      yield({
        progress: (i + 1) / total.to_f,
        current: structure['name'],
        status: "Warming #{i+1}/#{total}"
      }) if block_given?

    rescue => e
      errors << {table_id: table_id, error: e.message}
    end
  end

  {
    status: "complete",
    warmed: warmed,
    errors: errors,
    total_records: warmed.sum { |t| t[:record_count] }
  }
end
```

**Response:**

```json
{
  "status": "complete",
  "warmed": [
    {
      "table_id": "tbl_123",
      "table_name": "Customers",
      "record_count": 1500
    },
    {
      "table_id": "tbl_456",
      "table_name": "Orders",
      "record_count": 5000
    }
  ],
  "total_records": 6500,
  "duration_seconds": 12.5
}
```

**Q4:** Prevent cache stampede?

**My Recommendation:** **Add simple locking**

**Problem:** Multiple concurrent warm requests → duplicate API calls

**Solution:**

```ruby
class CacheLayer
  def initialize
    @warming_locks = {}  # {table_id => true/false}
  end

  def cache_table_records(table_id, structure, records, ttl: nil)
    # Check if already warming
    return {status: "already_warming"} if @warming_locks[table_id]

    # Acquire lock
    @warming_locks[table_id] = true

    begin
      # ... cache logic ...
    ensure
      # Release lock
      @warming_locks.delete(table_id)
    end
  end
end
```

---

### YOUR DECISION

**Warming triggers (v1.6):**

- [x] Manual only
- [ ] Auto on startup
- [ ] Scheduled
- [ ] Usage-based

**Warming strategies:**

- [x] Top N accessed tables
- [ ] All tables in solution
- [x] User-specified list
- [ ] Critical tables from config

**Show progress?** [x] Yes [ ] No

**Timeline:** [x] v1.6 [ ] v1.7 [ ] v2.0

**Notes:**

---

## Item 11: Add Cache Stats to API Stats Endpoint

**Status:** ⏳ Pending

### Context

Current `get_api_stats` tool shows API call metrics. Add cache metrics too.

### Questions

**Q1:** Extend existing response or new tool?

**My Recommendation:** **Extend existing `get_api_stats`**

**Why?**

- Users want holistic view: API calls + cache performance
- Shows relationship: cache hits = API calls avoided
- Single tool is simpler

**Current response:**

```json
{
  "summary": {
    "total_calls": 150,
    "first_call": "...",
    "last_call": "...",
    "unique_users": 1
  },
  "by_method": { "GET": 50, "POST": 100 },
  "by_solution": { "sol_123": 150 },
  "by_table": { "tbl_abc": 80 }
}
```

**Proposed response (extended):**

```json
{
  "api_stats": {
    "summary": { ... },
    "by_method": { ... },
    "by_solution": { ... }
  },
  "cache_stats": {
    "summary": {
      "total_hits": 1250,
      "total_misses": 150,
      "hit_rate": 0.893,
      "api_calls_avoided": 1250,
      "estimated_tokens_saved": 875000
    },
    "by_resource": {
      "solutions": {"hits": 45, "misses": 1, "hit_rate": 0.978},
      "tables": {"hits": 120, "misses": 8, "hit_rate": 0.937},
      "records": {"hits": 1085, "misses": 141, "hit_rate": 0.885}
    },
    "by_table": [
      {
        "table_id": "tbl_123",
        "table_name": "Customers",
        "hits": 450,
        "misses": 50,
        "hit_rate": 0.9
      }
    ]
  },
  "efficiency": {
    "api_calls_total": 150,
    "api_calls_saved": 1250,
    "savings_ratio": 8.33,
    "message": "Cache saved 8.3x API calls"
  }
}
```

**Q2:** What cache metrics to include?

**My Recommendation:** **Start with high-level, add detail on request**

**Always included (summary):**

- Total hits/misses
- Hit rate
- API calls avoided
- Estimated token savings

**Optional (query parameter):**

```ruby
get_api_stats(include_details: true)
# Returns detailed per-table breakdown

get_api_stats(include_history: true)
# Returns cache performance over time
```

**Q3:** Calculate token savings?

**My Recommendation:** **Use conservative estimates**

**Approach:**

```ruby
def estimate_tokens_saved
  # Average response sizes (conservative estimates)
  TOKENS_PER_RESPONSE = {
    'solutions' => 500,   # List of 100+ solutions
    'tables' => 300,      # List of tables
    'records' => 800      # List of records (10 records)
  }

  total_saved = 0

  cache_stats.each do |resource, stats|
    tokens_per_hit = TOKENS_PER_RESPONSE[resource] || 500
    total_saved += stats['hits'] * tokens_per_hit
  end

  total_saved
end
```

**Q4:** Real-time or historical?

**My Recommendation:** **Both, with time range filter**

**Default:** Current session stats
**Optional:** Lifetime stats, last 7 days, last 30 days

```ruby
get_api_stats(time_range: 'session')   # Current session only
get_api_stats(time_range: '7d')        # Last 7 days
get_api_stats(time_range: 'all')       # Lifetime
```

---

### YOUR DECISION

**Extend get_api_stats or create new tool?** [x] Extend [ ] New tool

**Metrics to include:**

- [x] Hit/miss counts
- [x] Hit rates
- [ ] API calls saved
- [x] Token savings estimate
- [x] Per-table breakdown
- [ ] Other: \***\*\_\_\_\*\***

**Time range filter?** [x] Yes [ ] No

**Timeline:** [x] v1.6 [ ] v1.7

**Notes:**

---

## Item 12: Analyze Refactoring Opportunities

**Status:** ⏳ Pending

### Context

`cache_layer.rb` is 1248 lines. API client modules could be simplified. Code review needed.

### Questions

**Q1:** What are the pain points?

**My Recommendation:** **Focus on these areas**

**Top 3 refactoring targets:**

**1. Split cache_layer.rb (1248 lines → ~400 lines each)**

```
cache_layer.rb (1248 lines) →
  ├── cache_layer.rb (core: 400 lines)
  │   - Table/record caching
  │   - Query interface
  │   - TTL management
  │
  ├── cache_migrations.rb (200 lines)
  │   - migrate_cache_tables_schema
  │   - migrate_api_call_log_schema
  │   - Version migrations
  │
  ├── cache_metadata.rb (300 lines)
  │   - Solutions caching
  │   - Table list caching
  │   - Metadata operations
  │
  └── cache_performance.rb (200 lines)
      - Performance tracking
      - Statistics
      - Hit/miss recording
```

**Benefits:**

- Easier to navigate
- Clear responsibilities
- Faster to test
- Simpler to understand

**2. Extract common API patterns**

Many API operation files repeat similar patterns:

```ruby
# Repeated pattern in workspace_operations, table_operations, etc.
def list_something(params)
  # Check cache
  cached = @cache.get_cached_something
  return cached if cached

  # Fetch from API
  response = api_request(:get, '/endpoint/')

  # Cache response
  @cache.cache_something(response)

  # Return
  response
end
```

**Refactor to:**

```ruby
module CachedApiOperation
  def cached_api_call(cache_key:, ttl:, &block)
    # Check cache
    cached = @cache.get(cache_key)
    return cached if cached

    # Fetch via block
    result = block.call

    # Cache result
    @cache.set(cache_key, result, ttl: ttl)

    result
  end
end

# Usage
def list_solutions
  cached_api_call(cache_key: 'solutions', ttl: 7.days) do
    api_request(:get, '/solutions/')
  end
end
```

**Benefits:**

- DRY (Don't Repeat Yourself)
- Consistent caching behavior
- Easier to add new operations
- Single place to fix cache bugs

**3. Simplify response formatters**

`response_formatter.rb` has complex nested logic. Could use strategy pattern:

```ruby
# Current: One big method with case statements
def filter_field_structure(field)
  case field['field_type']
  when 'statusfield'
    # ... 20 lines ...
  when 'linkedrecordfield'
    # ... 15 lines ...
  # ... etc
  end
end

# Refactored: Strategy pattern
class FieldFormatter
  def self.format(field)
    formatter = FORMATTERS[field['field_type']] || DefaultFormatter
    formatter.format(field)
  end
end

class StatusFieldFormatter
  def self.format(field)
    # ... 20 lines ...
  end
end

FORMATTERS = {
  'statusfield' => StatusFieldFormatter,
  'linkedrecordfield' => LinkedRecordFieldFormatter,
  # ...
}
```

**Q2:** Priority order for refactoring?

**My Recommendation:**

| Priority  | Refactoring             | Effort    | Impact | Timeline |
| --------- | ----------------------- | --------- | ------ | -------- |
| 🔴 High   | Split cache_layer.rb    | 4-6 hours | High   | v1.6     |
| 🟡 Medium | Extract API patterns    | 3-4 hours | Medium | v1.7     |
| 🟢 Low    | Strategy for formatters | 2-3 hours | Low    | v2.0     |

**Q3:** Breaking changes?

**My Recommendation:** **No breaking changes - internal refactor only**

**Public API stays the same:**

```ruby
# Before and after
cache = CacheLayer.new
cache.cache_table_records(table_id, structure, records)
result = cache.query(table_id).where(status: 'Active').execute
```

**Internal structure changes:**

```ruby
# Before
require 'smartsuite/cache_layer'

# After
require 'smartsuite/cache/cache_layer'
require 'smartsuite/cache/cache_metadata'
require 'smartsuite/cache/cache_performance'
require 'smartsuite/cache/cache_migrations'
```

**Users don't need to change code** - backward compatible requires.

**Q4:** Add to roadmap or defer?

**My Recommendation:** **Split into phases**

**v1.6:** Split cache_layer.rb only (highest impact)
**v1.7:** Extract API patterns
**v2.0:** Strategy pattern for formatters

This spreads work across releases and gets immediate benefit from splitting cache_layer.rb.

---

### YOUR DECISION

**Refactoring priorities:**

1. [x] Split cache_layer.rb
2. [x] Extract API patterns
3. [x] Strategy for formatters
4. [ ] Other: \***\*\_\_\_\*\***

**Timeline:**

- v1.6: \***\*\_\_\_\*\***
- v1.7: \***\*\_\_\_\*\***
- v2.0: \***\*\_\_\_\*\***

**Breaking changes acceptable?** [x] Yes [ ] No [ ] Only internal

**Notes:**

---

## Summary & Next Steps

### Decision Status

| Item                     | Status | Priority | Target |
| ------------------------ | ------ | -------- | ------ |
| 1. Rename table          | ⏳     | High     | v1.6   |
| 2. Schema review         | ⏳     | High     | v1.6   |
| 3. list_records analysis | ⏳     | High     | v1.6   |
| 4. Better naming         | ⏳     | High     | v1.6   |
| 5. Increase TTL          | ⏳     | High     | v1.6   |
| 6. Cache refresh         | ⏳     | High     | v1.6   |
| 7. Remove old code       | ⏳     | High     | v2.0   |
| 8. Cache metadata        | ⏳     | High     | v1.6   |
| 9. Better prompts        | ⏳     | High     | v1.6   |
| 10. Cache warming        | ⏳     | High     | v1.6   |
| 11. Cache stats          | ⏳     | High     | v1.6   |
| 12. Refactoring          | ⏳     | High     | v1.6   |

### After Filling This Out

1. **Review** - Check all decisions make sense together
2. **Prioritize** - Mark which to do first in v1.6
3. **Create issues** - One GitHub issue per approved item
4. **Update ROADMAP.md** - Reflect final decisions
5. **Start implementing** - Tackle highest priority items

### Questions?

Add any questions or concerns here:

**General questions:**

**Specific items needing clarification:**

**Additional considerations:**

---

**Last Updated:** [2025-11-15 16:25 PT]
**Next Review:** [When to revisit these decisions]
