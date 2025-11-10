# SmartSuite MCP Server: SQLite Caching Layer Design

## Overview

This design document outlines a **SQLite-based caching layer** for the SmartSuite MCP server. SQLite provides:
- **Persistent caching** across sessions (unlike in-memory)
- **Zero deployment complexity** (single file database)
- **Query capabilities** for efficient data retrieval
- **Token optimization** through pre-computed summaries and indexed lookups

## Design Goals

1. **Simplify Deployment**: Single SQLite file, no external database required
2. **Reduce Token Usage**: Store and query detailed information without sending to AI
3. **Improve Performance**: Reduce API calls by 75-85% for metadata operations
4. **Enable Advanced Queries**: Support filtering, aggregation, and analysis directly in cache
5. **Maintain Accuracy**: Implement TTL and invalidation to prevent stale data

---

## SQLite Schema Design

### Database Location
```ruby
~/.smartsuite_mcp_cache.db  # User home directory for portability
```

### Core Tables

#### 1. `cache_entries` - Generic Cache Storage
```sql
CREATE TABLE cache_entries (
  key TEXT PRIMARY KEY,           -- Cache key (e.g., "solutions", "table:123:structure")
  value TEXT NOT NULL,            -- JSON-encoded data
  created_at INTEGER NOT NULL,    -- Unix timestamp
  expires_at INTEGER NOT NULL,    -- Unix timestamp (TTL)
  category TEXT NOT NULL,         -- 'solution', 'table', 'member', 'record', etc.
  metadata TEXT,                  -- JSON metadata (size, source, filters)
  access_count INTEGER DEFAULT 0, -- Hit count
  last_accessed_at INTEGER        -- Last read timestamp
);

CREATE INDEX idx_expires_at ON cache_entries(expires_at);
CREATE INDEX idx_category ON cache_entries(category);
CREATE INDEX idx_last_accessed ON cache_entries(last_accessed_at);
```

**Purpose**: Store all cached API responses with TTL and metadata

**Key Format Examples**:
- `solutions` - All solutions list
- `solutions:with_activity` - Solutions with activity data
- `table:abc123:structure` - Table structure
- `records:abc123:filter_hash:field_hash` - Filtered records
- `members:all` - All members
- `members:solution:xyz789` - Members by solution

#### 2. `solutions` - Normalized Solution Cache
```sql
CREATE TABLE solutions (
  id TEXT PRIMARY KEY,              -- Solution ID
  name TEXT NOT NULL,
  logo TEXT,
  status TEXT,                      -- 'active', 'archived', 'hidden'
  hidden BOOLEAN DEFAULT 0,
  created_on INTEGER,
  last_access INTEGER,              -- Last access timestamp
  records_count INTEGER DEFAULT 0,
  members_count INTEGER DEFAULT 0,
  applications_count INTEGER DEFAULT 0,
  automation_count INTEGER DEFAULT 0,
  has_demo_data BOOLEAN DEFAULT 0,
  permissions TEXT,                 -- JSON: owners, editors, viewers
  metadata TEXT,                    -- Other fields as JSON
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX idx_solutions_name ON solutions(name);
CREATE INDEX idx_solutions_status ON solutions(status);
CREATE INDEX idx_solutions_last_access ON solutions(last_access);
CREATE INDEX idx_solutions_hidden ON solutions(hidden);
```

**Purpose**: Queryable solution metadata for analysis without sending to AI

**Use Cases**:
- Find solutions by owner: `SELECT * FROM solutions WHERE json_extract(permissions, '$.owners') LIKE '%user_id%'`
- Find inactive solutions: `SELECT * FROM solutions WHERE last_access < ? AND records_count > 10`
- Aggregate by status: `SELECT status, COUNT(*) FROM solutions GROUP BY status`

#### 3. `tables` - Normalized Table Cache
```sql
CREATE TABLE tables (
  id TEXT PRIMARY KEY,              -- Table ID
  name TEXT NOT NULL,
  solution_id TEXT NOT NULL,
  structure TEXT,                   -- JSON field structure (filtered)
  field_count INTEGER DEFAULT 0,
  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (solution_id) REFERENCES solutions(id) ON DELETE CASCADE
);

CREATE INDEX idx_tables_solution ON tables(solution_id);
CREATE INDEX idx_tables_name ON tables(name);
CREATE INDEX idx_tables_expires ON tables(expires_at);
```

**Purpose**: Fast table lookups without API calls

**Use Cases**:
- Find tables in solution: `SELECT * FROM tables WHERE solution_id = ?`
- Search by name: `SELECT * FROM tables WHERE name LIKE ?`
- Get field structure: `SELECT structure FROM tables WHERE id = ?`

#### 4. `fields` - Field Definitions for Advanced Queries
```sql
CREATE TABLE fields (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_id TEXT NOT NULL,
  slug TEXT NOT NULL,
  label TEXT NOT NULL,
  field_type TEXT NOT NULL,         -- 'text', 'number', 'single_select', etc.
  required BOOLEAN DEFAULT 0,
  unique BOOLEAN DEFAULT 0,
  primary_field BOOLEAN DEFAULT 0,
  choices TEXT,                     -- JSON array for select fields
  linked_application TEXT,          -- For linked record fields
  metadata TEXT,                    -- Other params as JSON
  cached_at INTEGER NOT NULL,
  UNIQUE(table_id, slug),
  FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
);

CREATE INDEX idx_fields_table ON fields(table_id);
CREATE INDEX idx_fields_type ON fields(field_type);
CREATE INDEX idx_fields_slug ON fields(slug);
```

**Purpose**: Enable field-level queries without parsing JSON

**Use Cases**:
- Find all select fields: `SELECT * FROM fields WHERE field_type IN ('single_select', 'multiple_select')`
- Get linked tables: `SELECT DISTINCT linked_application FROM fields WHERE field_type = 'linkedrecord'`
- Count fields by type: `SELECT field_type, COUNT(*) FROM fields GROUP BY field_type`

#### 5. `members` - Member Cache for Fast Lookups
```sql
CREATE TABLE members (
  id TEXT PRIMARY KEY,              -- Member ID
  first_name TEXT,
  last_name TEXT,
  email TEXT,
  role TEXT,                        -- 'admin', 'member', 'guest'
  active BOOLEAN DEFAULT 1,
  solutions TEXT,                   -- JSON array of solution IDs
  teams TEXT,                       -- JSON array of team IDs
  metadata TEXT,                    -- Other fields as JSON
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX idx_members_email ON members(email);
CREATE INDEX idx_members_role ON members(role);
CREATE INDEX idx_members_active ON members(active);
CREATE INDEX idx_members_expires ON members(expires_at);
```

**Purpose**: Fast member lookups and filtering without fetching all 1000 members

**Use Cases**:
- Find by email: `SELECT * FROM members WHERE email LIKE ?`
- Members in solution: `SELECT * FROM members WHERE json_extract(solutions, '$') LIKE '%sol_id%'`
- Active admins: `SELECT * FROM members WHERE role = 'admin' AND active = 1`

#### 6. `cache_stats` - Cache Performance Metrics
```sql
CREATE TABLE cache_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,           -- 'solution', 'table', 'member', etc.
  operation TEXT NOT NULL,          -- 'hit', 'miss', 'invalidation', 'eviction'
  key TEXT,                         -- Cache key involved
  timestamp INTEGER NOT NULL,
  metadata TEXT                     -- Additional context as JSON
);

CREATE INDEX idx_stats_timestamp ON cache_stats(timestamp);
CREATE INDEX idx_stats_category ON cache_stats(category);
CREATE INDEX idx_stats_operation ON cache_stats(operation);
```

**Purpose**: Track cache effectiveness and identify optimization opportunities

---

## TTL (Time-To-Live) Strategy

### TTL Values by Data Type

**Note**: The implemented design uses **natural TTL expiration only** - NO automatic invalidation on mutations.

| Data Type | TTL | Rationale |
|-----------|-----|-----------|
| **Solutions (base)** | 24 hours | Rarely renamed/deleted |
| **Solutions (with activity)** | 2 hours | `last_access` changes frequently |
| **Table structures** | 12 hours | Fields added infrequently |
| **Table list** | 12 hours | Very stable |
| **Teams** | 12 hours | Planned changes |
| **Members (all)** | 6 hours | Batch updates |
| **Members (filtered)** | 4 hours | More dynamic |
| **Records (cached table)** | 4 hours | Default table-based TTL (configurable) |
| **Comments** | Not cached | Use direct API calls |

### TTL Implementation

```ruby
# In cache_layer.rb
class CacheLayer
  TTL_SECONDS = {
    solutions: 24 * 3600,           # 24 hours
    solutions_activity: 2 * 3600,   # 2 hours
    table_structure: 12 * 3600,     # 12 hours
    table_list: 12 * 3600,          # 12 hours
    teams: 12 * 3600,               # 12 hours
    members_all: 6 * 3600,          # 6 hours
    members_filtered: 4 * 3600,     # 4 hours
    records: 5 * 60,                # 5 minutes
    comments: 2 * 60                # 2 minutes
  }

  def cache_key_ttl(key)
    case key
    when /^solutions:with_activity/
      TTL_SECONDS[:solutions_activity]
    when /^solutions/
      TTL_SECONDS[:solutions]
    when /^table:.*:structure$/
      TTL_SECONDS[:table_structure]
    when /^records:/
      TTL_SECONDS[:records]
    # ... etc
    else
      3600  # Default 1 hour
    end
  end
end
```

---

## Cache Expiration Strategy

### Natural TTL Expiration (No Automatic Invalidation)

**Implemented Design**: The cache uses **natural TTL expiration only** - mutations do NOT trigger cache invalidation.

**Rationale**:
- User tolerance for slightly stale data (up to TTL duration)
- Avoids expensive re-fetching on every mutation
- Simplifies implementation and reduces API calls
- Mutations are often batched, making per-mutation invalidation wasteful

**How Records Work**:
```ruby
# When cache enabled and records requested:
# 1. Check if cache valid (not expired)
# 2. If invalid/expired: Fetch ALL records (1000 record batches) and cache
# 3. Query cached records with local filtering
# 4. Cache expires naturally after TTL (default: 4 hours)

# Mutations do NOT invalidate cache:
def create_record(table_id, data)
  api_request(:post, "/applications/#{table_id}/records/", data)
  # NO cache invalidation - cache expires naturally by TTL
end
```

**Manual Refresh Option**:
```ruby
# If user needs fresh data immediately after mutation:
list_records(table_id, limit: 100, fields: ['name'], bypass_cache: true)
# Forces API call and cache refresh
```

### Manual Cache Management

Expose tools for manual cache control:

```ruby
# New MCP tools
{
  "name": "clear_cache",
  "description": "Clear cache entries by category or pattern",
  "parameters": {
    "category": "solution|table|member|record|all",
    "pattern": "Optional key pattern (e.g., 'table:*')"
  }
}

{
  "name": "cache_info",
  "description": "Get cache statistics and health metrics",
  "returns": {
    "total_entries": 1234,
    "by_category": {"solution": 100, "table": 50, ...},
    "hit_rate": "85.3%",
    "size_mb": 12.5,
    "oldest_entry": "2025-01-08 10:23:45",
    "expired_entries": 15
  }
}
```

---

## Query Interfaces for Token Optimization

### 1. Filtered Queries (Return Minimal Data)

```ruby
# Instead of sending full solution list to AI:
# OLD: 110 solutions × 200 tokens = 22,000 tokens
# NEW: Query cache and return only what's needed

def list_solutions_by_criteria(filters)
  query = "SELECT id, name, status FROM solutions WHERE 1=1"
  params = []

  if filters[:status]
    query += " AND status = ?"
    params << filters[:status]
  end

  if filters[:min_records]
    query += " AND records_count >= ?"
    params << filters[:min_records]
  end

  if filters[:owner]
    query += " AND json_extract(permissions, '$.owners') LIKE ?"
    params << "%#{filters[:owner]}%"
  end

  db.execute(query, params)
end

# AI receives: 5 solutions × 50 tokens = 250 tokens (91% savings)
```

### 2. Aggregation Queries (Pre-computed Summaries)

```ruby
# Provide summaries instead of raw data
def solution_usage_summary
  {
    total: db.execute("SELECT COUNT(*) FROM solutions")[0][0],
    by_status: db.execute("SELECT status, COUNT(*) FROM solutions GROUP BY status"),
    inactive: db.execute("SELECT COUNT(*) FROM solutions WHERE last_access < ?",
                         (Time.now - 90*24*3600).to_i)[0][0],
    avg_records: db.execute("SELECT AVG(records_count) FROM solutions")[0][0],
    top_5_by_records: db.execute("SELECT name, records_count FROM solutions
                                  ORDER BY records_count DESC LIMIT 5")
  }
end

# AI receives: Summary object (~200 tokens) vs full data (~10,000 tokens)
```

### 3. Field Search and Analysis

```ruby
# Find fields without fetching table structures
def find_fields_by_type(field_type, table_ids: nil)
  query = "SELECT table_id, slug, label FROM fields WHERE field_type = ?"
  params = [field_type]

  if table_ids
    placeholders = table_ids.map { '?' }.join(',')
    query += " AND table_id IN (#{placeholders})"
    params += table_ids
  end

  db.execute(query, params)
end

# Example: Find all status fields across 50 tables
# OLD: 50 API calls × 200 tokens = 10,000 tokens
# NEW: 1 cache query = 100 tokens (99% savings)
```

### 4. Relationship Traversal

```ruby
# Navigate solution → tables → fields without API calls
def get_solution_schema(solution_id)
  {
    solution: db.execute("SELECT id, name FROM solutions WHERE id = ?", solution_id).first,
    tables: db.execute("SELECT id, name, field_count FROM tables WHERE solution_id = ?", solution_id),
    total_fields: db.execute("SELECT SUM(field_count) FROM tables WHERE solution_id = ?", solution_id)[0][0]
  }
end

# Entire solution schema map: ~500 tokens vs 5+ API calls
```

---

## Integration with Existing Code

### 1. CacheLayer Module (`lib/smartsuite/cache_layer.rb`)

```ruby
require 'sqlite3'
require 'json'
require 'digest'

module SmartSuite
  class CacheLayer
    def initialize(db_path: nil)
      @db_path = db_path || File.expand_path('~/.smartsuite_mcp_cache.db')
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true
      setup_tables
    end

    def get(key)
      # Check cache_entries first (generic cache)
      result = @db.execute(
        "SELECT value, expires_at FROM cache_entries WHERE key = ? AND expires_at > ?",
        key, Time.now.to_i
      ).first

      if result
        record_hit(key)
        JSON.parse(result['value'])
      else
        record_miss(key)
        nil
      end
    end

    def set(key, value, ttl: nil, category: 'generic', metadata: {})
      ttl_seconds = ttl || cache_key_ttl(key)
      expires_at = Time.now.to_i + ttl_seconds

      @db.execute(
        "INSERT OR REPLACE INTO cache_entries
         (key, value, created_at, expires_at, category, metadata, access_count, last_accessed_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?)",
        key, value.to_json, Time.now.to_i, expires_at, category, metadata.to_json, Time.now.to_i
      )

      # Also update normalized tables if applicable
      update_normalized_tables(key, value, category, expires_at)
    end

    def invalidate(pattern)
      # Implementation from earlier section
    end

    def query(sql, *params)
      @db.execute(sql, params)
    end

    private

    def setup_tables
      # Create all tables from schema section
    end

    def update_normalized_tables(key, value, category, expires_at)
      case category
      when 'solution'
        # Parse and insert into solutions table
        upsert_solutions(value, expires_at)
      when 'table'
        # Parse and insert into tables + fields
        upsert_table_structure(value, expires_at)
      when 'member'
        # Parse and insert into members
        upsert_members(value, expires_at)
      end
    end

    def record_hit(key)
      @db.execute(
        "UPDATE cache_entries SET access_count = access_count + 1, last_accessed_at = ? WHERE key = ?",
        Time.now.to_i, key
      )
      @db.execute(
        "INSERT INTO cache_stats (category, operation, key, timestamp) VALUES (?, 'hit', ?, ?)",
        extract_category(key), key, Time.now.to_i
      )
    end

    def record_miss(key)
      @db.execute(
        "INSERT INTO cache_stats (category, operation, key, timestamp) VALUES (?, 'miss', ?, ?)",
        extract_category(key), key, Time.now.to_i
      )
    end
  end
end
```

### 2. Integration with HttpClient (`lib/smartsuite/api/http_client.rb`)

```ruby
module SmartSuite
  module API
    module HttpClient
      def api_request(method, endpoint, body: nil, query_params: {}, cacheable: false, cache_key: nil, ttl: nil)
        # Check cache first for GET requests
        if cacheable && method == :get && cache_key && @cache
          cached = @cache.get(cache_key)
          return cached if cached

          log_metric("→ Cache MISS: #{cache_key}")
        end

        # Make API request
        response = make_request(method, endpoint, body: body, query_params: query_params)

        # Track with ApiStatsTracker
        track_api_call(method, endpoint, ...)

        # Cache successful responses
        if cacheable && cache_key && response && @cache
          @cache.set(cache_key, response, ttl: ttl, category: extract_category(cache_key))
          log_metric("→ Cache SET: #{cache_key}")
        end

        response
      end
    end
  end
end
```

### 3. Modify Workspace Operations

```ruby
# lib/smartsuite/api/workspace_operations.rb

def list_solutions(include_activity_data: false, fields: nil)
  cache_key = include_activity_data ? "solutions:with_activity" : "solutions"

  # Try cache first
  if @cache
    cached = @cache.get(cache_key)
    if cached
      log_metric("→ Using cached solutions (#{cached.size} solutions)")
      return apply_field_filter(cached, fields) if fields
      return cached
    end
  end

  # Cache miss - fetch from API
  result = api_request(
    :get,
    'solutions/',
    cacheable: true,
    cache_key: cache_key,
    ttl: include_activity_data ? 2.hours : 24.hours
  )

  # Return with optional field filtering
  apply_field_filter(result, fields) if fields
  result
end

def get_table(table_id)
  cache_key = "table:#{table_id}:structure"

  # Try cache first
  if @cache
    cached = @cache.get(cache_key)
    return cached if cached
  end

  # Cache miss - fetch from API
  result = api_request(
    :get,
    "applications/#{table_id}/",
    cacheable: true,
    cache_key: cache_key,
    ttl: 12.hours
  )

  result
end
```

### 4. Mutation Operations (No Cache Invalidation)

```ruby
# lib/smartsuite/api/field_operations.rb

def add_field(table_id, field_data, field_position: {}, auto_fill_structure_layout: true)
  result = api_request(:post, "applications/#{table_id}/add_field/", ...)

  # NO cache invalidation - cache expires naturally by TTL
  # Users can use bypass_cache: true if immediate refresh needed

  result
end

def update_field(table_id, field_data)
  result = api_request(:put, "applications/#{table_id}/change_field/", ...)

  # NO cache invalidation

  result
end

# lib/smartsuite/api/record_operations.rb

def create_record(table_id, data)
  api_request(:post, "/applications/#{table_id}/records/", data)
  # NO cache invalidation
end

def update_record(table_id, record_id, data)
  api_request(:patch, "/applications/#{table_id}/records/#{record_id}/", data)
  # NO cache invalidation
end
```

### 5. Initialize Cache in SmartSuiteClient

```ruby
# lib/smartsuite_client.rb

class SmartSuiteClient
  include SmartSuite::API::HttpClient
  include SmartSuite::API::WorkspaceOperations
  # ... other modules

  def initialize(api_key:, account_id:, cache_enabled: true, cache_path: nil)
    @api_key = api_key
    @account_id = account_id
    @base_uri = URI('https://app.smartsuite.com/api/v1/')

    # Initialize cache layer
    if cache_enabled
      @cache = SmartSuite::CacheLayer.new(db_path: cache_path)
    end

    # Initialize API stats tracker
    @stats_tracker = ApiStatsTracker.new
  end
end
```

### 6. Expose Cache Management Tools

```ruby
# Add to lib/smartsuite/mcp/tool_registry.rb

{
  "name": "get_cache_stats",
  "description": "Get cache performance statistics and metrics",
  "inputSchema": {
    "type": "object",
    "properties": {
      "category": {
        "type": "string",
        "enum": ["all", "solution", "table", "member", "record"],
        "description": "Filter stats by category"
      },
      "time_range": {
        "type": "string",
        "enum": ["hour", "day", "week", "all"],
        "description": "Time range for statistics"
      }
    }
  }
},
{
  "name": "clear_cache",
  "description": "Clear cache entries by category or pattern",
  "inputSchema": {
    "type": "object",
    "properties": {
      "category": {
        "type": "string",
        "enum": ["all", "solution", "table", "member", "record"]
      },
      "pattern": {
        "type": "string",
        "description": "Optional key pattern with wildcards (e.g., 'table:*')"
      }
    }
  }
},
{
  "name": "query_cache",
  "description": "Query normalized cache tables for efficient lookups",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query_type": {
        "type": "string",
        "enum": ["solutions_by_status", "tables_by_solution", "fields_by_type", "inactive_solutions", "solution_schema"]
      },
      "parameters": {
        "type": "object",
        "description": "Query-specific parameters"
      }
    }
  }
}
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Priority: CRITICAL)
**Estimated Time**: 4-6 hours
**Impact**: 75-85% API reduction for metadata

**Tasks**:
1. Create `lib/smartsuite/cache_layer.rb` with SQLite setup
2. Implement schema creation (cache_entries, solutions, tables, fields, members, cache_stats)
3. Implement basic `get()`, `set()`, `invalidate()` methods
4. Add TTL cleanup on initialization
5. Write unit tests for cache operations

**Files to Create**:
- `lib/smartsuite/cache_layer.rb` (~300 lines)
- `test/test_cache_layer.rb` (~200 lines)

**Files to Modify**:
- `lib/smartsuite_client.rb` - Initialize cache (5 lines)

### Phase 2: Integration with API Operations (Priority: HIGH)
**Estimated Time**: 5-7 hours
**Impact**: Enable caching for high-frequency endpoints

**Tasks**:
1. Add cache wrapper to `http_client.rb`
2. Update `list_solutions()` to use cache
3. Update `get_table()` to use cache
4. Update `list_tables()` to use cache
5. Update `list_members()` to use cache
6. Add invalidation hooks to mutation methods
7. Update tests

**Files to Modify**:
- `lib/smartsuite/api/http_client.rb` - Add cache wrapper (~30 lines)
- `lib/smartsuite/api/workspace_operations.rb` - Cache solutions (~20 lines)
- `lib/smartsuite/api/table_operations.rb` - Cache tables/structures (~25 lines)
- `lib/smartsuite/api/member_operations.rb` - Cache members (~20 lines)
- `lib/smartsuite/api/field_operations.rb` - Invalidation hooks (~15 lines)
- `lib/smartsuite/api/record_operations.rb` - Invalidation hooks (~15 lines)

### Phase 3: Normalized Tables & Query Interfaces (Priority: MEDIUM)
**Estimated Time**: 4-5 hours
**Impact**: Enable advanced queries and token optimization

**Tasks**:
1. Implement `update_normalized_tables()` for solutions, tables, fields
2. Implement `upsert_solutions()`, `upsert_table_structure()`, `upsert_members()`
3. Create query methods (list_solutions_by_criteria, find_fields_by_type, etc.)
4. Add MCP tools (query_cache, get_cache_stats, clear_cache)
5. Update tool registry
6. Write tests for query interfaces

**Files to Modify**:
- `lib/smartsuite/cache_layer.rb` - Add query methods (~150 lines)
- `lib/smartsuite/mcp/tool_registry.rb` - Add cache tools (~100 lines)
- `smartsuite_server.rb` - Add tool handlers (~50 lines)
- `test/test_cache_layer.rb` - Add query tests (~100 lines)

### Phase 4: Cache Stats & Monitoring (Priority: LOW)
**Estimated Time**: 2-3 hours
**Impact**: Visibility into cache performance

**Tasks**:
1. Integrate cache stats with ApiStatsTracker
2. Implement cache health metrics
3. Add periodic cleanup of expired entries
4. Create cache performance dashboard (stats tool)
5. Update documentation

**Files to Modify**:
- `lib/api_stats_tracker.rb` - Add cache metrics (~50 lines)
- `lib/smartsuite/cache_layer.rb` - Add cleanup methods (~30 lines)
- `CLAUDE.md` - Document cache usage (~100 lines)

### Phase 5: Advanced Features (Priority: OPTIONAL)
**Estimated Time**: 3-4 hours
**Impact**: Further optimization opportunities

**Tasks**:
1. Implement cache warming for common queries
2. Add LRU eviction for size limits
3. Implement conditional caching for records (only with filters)
4. Add cache compression for large responses
5. Implement cache export/import for backup

---

## Testing Strategy

### Unit Tests

```ruby
# test/test_cache_layer.rb

class TestCacheLayer < Minitest::Test
  def setup
    @cache = SmartSuite::CacheLayer.new(db_path: ':memory:')  # In-memory for tests
  end

  def test_basic_get_set
    @cache.set('test_key', {'data' => 'value'}, ttl: 3600)
    result = @cache.get('test_key')
    assert_equal({'data' => 'value'}, result)
  end

  def test_ttl_expiration
    @cache.set('expire_key', {'data' => 'value'}, ttl: 1)
    sleep(2)
    result = @cache.get('expire_key')
    assert_nil(result)
  end

  def test_invalidation_exact
    @cache.set('table:123:structure', {}, ttl: 3600)
    @cache.invalidate('table:123:structure')
    result = @cache.get('table:123:structure')
    assert_nil(result)
  end

  def test_invalidation_wildcard
    @cache.set('records:123:filter1', {}, ttl: 3600)
    @cache.set('records:123:filter2', {}, ttl: 3600)
    @cache.invalidate('records:123:*')
    assert_nil(@cache.get('records:123:filter1'))
    assert_nil(@cache.get('records:123:filter2'))
  end

  def test_normalized_solutions_upsert
    solution_data = {'id' => 'sol_123', 'name' => 'Test Solution', 'status' => 'active'}
    @cache.set('solutions', [solution_data], category: 'solution', ttl: 3600)

    result = @cache.query("SELECT * FROM solutions WHERE id = 'sol_123'")
    assert_equal('Test Solution', result.first['name'])
  end

  def test_query_solutions_by_status
    # Setup test data
    @cache.set('solutions', [
      {'id' => 'sol_1', 'name' => 'Active', 'status' => 'active'},
      {'id' => 'sol_2', 'name' => 'Archived', 'status' => 'archived'}
    ], category: 'solution', ttl: 3600)

    result = @cache.list_solutions_by_criteria(status: 'active')
    assert_equal(1, result.size)
    assert_equal('Active', result.first['name'])
  end

  def test_cache_stats
    @cache.set('test1', {}, ttl: 3600)
    @cache.get('test1')  # Hit
    @cache.get('test2')  # Miss

    stats = @cache.stats
    assert_equal(1, stats[:hits])
    assert_equal(1, stats[:misses])
  end
end
```

### Integration Tests

```ruby
# test/test_smartsuite_server_cache.rb

def test_list_solutions_caching
  # First call - cache miss
  result1 = call_tool('list_solutions', {})
  assert_includes(@stderr_output, 'Cache MISS')

  # Second call - cache hit
  result2 = call_tool('list_solutions', {})
  assert_includes(@stderr_output, 'Using cached solutions')

  # Results should be identical
  assert_equal(result1, result2)
end

def test_cache_natural_expiration_on_mutation
  # Get table structure (cache it)
  table = call_tool('get_table', {table_id: 'abc123'})

  # Add a field (does NOT invalidate cache)
  call_tool('add_field', {table_id: 'abc123', field_data: {...}})

  # Next get should return cached data (even though structure changed)
  result = call_tool('get_table', {table_id: 'abc123'})
  assert_includes(@stderr_output, 'Using cached')  # Cache still valid

  # To get fresh data, use bypass_cache:
  fresh = call_tool('list_records', {table_id: 'abc123', fields: ['name'], bypass_cache: true})
  assert_includes(@stderr_output, 'Cache MISS')
end
```

### Performance Tests

```ruby
def test_cache_performance_improvement
  # Measure without cache
  start = Time.now
  10.times { call_tool('list_solutions', {}) }
  time_without_cache = Time.now - start

  # Enable cache and measure
  @client.cache_enabled = true
  start = Time.now
  10.times { call_tool('list_solutions', {}) }
  time_with_cache = Time.now - start

  # Cache should be at least 5x faster
  assert(time_with_cache < time_without_cache / 5)
end
```

---

## Migration Path

### 1. Existing In-Memory Cache (@teams_cache)

Current implementation in `member_operations.rb:246`:
```ruby
@teams_cache ||= {}
```

**Migration Strategy**:
1. Keep `@teams_cache` for backwards compatibility (short-term)
2. Add SQLite cache as primary storage
3. Deprecate `@teams_cache` after validation
4. Remove in-memory cache in next major version

**Transition Code**:
```ruby
def list_teams
  # Try SQLite cache first
  if @cache
    cached = @cache.get('teams:list')
    return cached if cached
  end

  # Fallback to in-memory cache
  if @teams_cache && !@teams_cache.empty?
    return @teams_cache.values
  end

  # Fetch from API
  result = api_request(:post, 'teams/list/', ...)

  # Store in both caches during transition
  @teams_cache = result.index_by { |t| t['id'] } if @teams_cache
  @cache.set('teams:list', result, ttl: 12.hours) if @cache

  result
end
```

### 2. Database Schema Migrations

**Version 1.0** (Initial schema):
- All tables from schema section

**Future versions**:
- Add migration system with version tracking
- Store schema version in `cache_metadata` table
- Implement automatic migration on initialization

```ruby
def migrate_schema
  current_version = get_schema_version

  case current_version
  when 0
    # Create initial tables
    create_v1_schema
    set_schema_version(1)
  when 1
    # Future migration
    alter_table_add_column(...)
    set_schema_version(2)
  end
end
```

---

## Performance Expectations

### Cache Hit Rates (Target)

| Endpoint | Expected Hit Rate | After N Calls |
|----------|------------------|---------------|
| list_solutions | 95%+ | After 1st call |
| get_table | 90%+ | After 1st call per table |
| list_tables | 90%+ | After 1st call per solution |
| list_members | 85%+ | After 1st call |
| list_records (filtered) | 60-70% | Depends on filters |

### Token Savings (Projected)

**Typical 30-minute session**:
- **Before**: 22 API calls, 3,060 tokens
- **After**: 4 API calls, 1,140 tokens
- **Savings**: 1,920 tokens (62.7% reduction)

**Heavy metadata exploration**:
- **Before**: 50 API calls, 8,000 tokens
- **After**: 8 API calls, 1,800 tokens
- **Savings**: 6,200 tokens (77.5% reduction)

### Database Size

**Expected cache size** (100 solutions, 500 tables, 1000 members):
- cache_entries: ~5 MB
- solutions: ~200 KB
- tables: ~2 MB
- fields: ~3 MB
- members: ~500 KB
- cache_stats: ~1 MB (grows over time, periodic cleanup)
- **Total**: ~12 MB

**With compression** (optional Phase 5):
- ~6-8 MB total

---

## Security Considerations

### 1. File Permissions

```ruby
def initialize(db_path: nil)
  @db_path = db_path || File.expand_path('~/.smartsuite_mcp_cache.db')

  # Ensure file has proper permissions (0600 - owner read/write only)
  if File.exist?(@db_path)
    File.chmod(0600, @db_path)
  end

  @db = SQLite3::Database.new(@db_path)
  File.chmod(0600, @db_path)  # Set again after creation
end
```

### 2. Data Sanitization

Never cache:
- API keys or tokens
- Passwords or credentials
- Sensitive permissions beyond basic access levels

### 3. Cache Clearing on Key Rotation

```ruby
# Detect API key changes and clear cache
def initialize(api_key:, ...)
  @api_key = api_key
  key_hash = Digest::SHA256.hexdigest(api_key)[0..7]

  # Check if API key changed
  stored_key_hash = read_metadata('api_key_hash')
  if stored_key_hash && stored_key_hash != key_hash
    @cache.clear_all  # New API key = different account
  end

  store_metadata('api_key_hash', key_hash)
end
```

---

## Advantages of SQLite vs In-Memory

| Aspect | In-Memory | SQLite | Winner |
|--------|-----------|---------|--------|
| **Persistence** | Lost on exit | Survives restarts | ✅ SQLite |
| **Query capability** | Manual filtering | SQL queries | ✅ SQLite |
| **Memory usage** | Grows unbounded | Disk-backed | ✅ SQLite |
| **Deployment** | Easy | Single file (easy) | ✅ Tie |
| **Speed** | Fastest | Very fast (~μs) | 🟡 In-memory (marginal) |
| **Concurrency** | Single process | Multi-process (with locking) | ✅ SQLite |
| **Debugging** | Difficult | `sqlite3` CLI tool | ✅ SQLite |
| **Eviction** | Manual LRU | TTL + SQL cleanup | ✅ SQLite |
| **Analytics** | Custom code | SQL aggregations | ✅ SQLite |

**Verdict**: SQLite is the clear winner for this use case.

---

## Example Usage Scenarios

### Scenario 1: Find Inactive Solutions

**Without cache** (traditional approach):
```ruby
# 1. Fetch all solutions (API call #1)
solutions = list_solutions(include_activity_data: true)  # 110 × 150 tokens = 16,500 tokens

# 2. Filter in Ruby
inactive = solutions.select { |s| s['last_access'] < 90.days.ago && s['records_count'] > 10 }
```

**With SQLite cache**:
```ruby
# Query cache directly
inactive = @cache.query(
  "SELECT id, name, last_access, records_count FROM solutions
   WHERE last_access < ? AND records_count > 10",
  (Time.now - 90*24*3600).to_i
)
# Result: 5 solutions × 50 tokens = 250 tokens (98.5% savings)
```

### Scenario 2: Get Solution Schema Overview

**Without cache**:
```ruby
# 1. Get solution (API call #1)
solution = get_solution('sol_123')  # 200 tokens

# 2. List tables (API call #2)
tables = list_tables(solution_id: 'sol_123')  # 400 tokens

# 3. Get each table structure (API calls #3-7)
structures = tables.map { |t| get_table(t['id']) }  # 5 × 200 = 1000 tokens

# Total: 7 API calls, 1,600 tokens
```

**With SQLite cache**:
```ruby
schema = @cache.query(
  "SELECT t.id, t.name, COUNT(f.id) as field_count, GROUP_CONCAT(f.field_type) as field_types
   FROM tables t
   LEFT JOIN fields f ON f.table_id = t.id
   WHERE t.solution_id = ?
   GROUP BY t.id",
  'sol_123'
)
# Result: 0 API calls (cache hit), 300 tokens (81% savings)
```

### Scenario 3: Find All Single Select Fields

**Without cache**:
```ruby
# Must fetch all table structures
tables = list_tables  # API call #1
structures = tables.map { |t| get_table(t['id']) }  # 50 API calls

# Filter in Ruby
single_selects = structures.flat_map do |s|
  s['structure'].select { |f| f['field_type'] == 'singleselectfield' }
end

# Total: 51 API calls, ~12,000 tokens
```

**With SQLite cache**:
```ruby
single_selects = @cache.query(
  "SELECT table_id, slug, label, choices FROM fields
   WHERE field_type = 'singleselectfield'"
)
# Result: 0 API calls, ~200 tokens (98.3% savings)
```

---

## Monitoring & Observability

### Cache Health Dashboard

New MCP tool: `get_cache_stats`

Example output:
```json
{
  "cache_health": {
    "total_entries": 1234,
    "expired_entries": 15,
    "size_mb": 12.5,
    "oldest_entry": "2025-01-08T10:23:45Z",
    "newest_entry": "2025-01-09T14:32:10Z"
  },
  "performance": {
    "hit_rate": "85.3%",
    "total_hits": 1520,
    "total_misses": 268,
    "avg_response_time_ms": 0.8
  },
  "by_category": {
    "solution": {
      "entries": 110,
      "hits": 450,
      "misses": 15,
      "hit_rate": "96.8%"
    },
    "table": {
      "entries": 500,
      "hits": 820,
      "misses": 120,
      "hit_rate": "87.2%"
    },
    "member": {
      "entries": 1000,
      "hits": 200,
      "misses": 80,
      "hit_rate": "71.4%"
    },
    "record": {
      "entries": 50,
      "hits": 50,
      "misses": 53,
      "hit_rate": "48.5%"
    }
  },
  "top_accessed": [
    {"key": "solutions", "access_count": 45},
    {"key": "table:abc123:structure", "access_count": 32},
    {"key": "members:all", "access_count": 28}
  ],
  "recommendations": [
    "Record cache hit rate is low (48.5%) - consider longer TTL or better key generation",
    "15 expired entries should be cleaned up"
  ]
}
```

### Integration with ApiStatsTracker

Extend existing stats file (`~/.smartsuite_mcp_stats.json`) with cache section:

```json
{
  "total_calls": 1234,
  "by_endpoint": {...},
  "cache": {
    "enabled": true,
    "total_hits": 1520,
    "total_misses": 268,
    "hit_rate": 0.853,
    "tokens_saved_estimate": 45600,
    "by_category": {...}
  }
}
```

---

## Conclusion

This SQLite-based caching design provides:

1. ✅ **Simple Deployment**: Single file database, no external dependencies
2. ✅ **Persistent Cache**: Survives restarts, accumulates over time
3. ✅ **Query Capabilities**: SQL-based filtering, aggregation, and joins
4. ✅ **Token Optimization**: 75-85% reduction for metadata operations
5. ✅ **API Call Reduction**: 30-50% fewer calls overall
6. ✅ **Monitoring**: Built-in stats and health metrics
7. ✅ **Maintainability**: Clear invalidation rules and TTL management

**Recommended Next Steps**:
1. Implement Phase 1 (core infrastructure)
2. Validate with unit tests
3. Deploy Phase 2 (API integration)
4. Monitor cache hit rates
5. Iterate on TTL values based on real usage
6. Implement Phase 3 (query interfaces) for maximum token savings

**Total Implementation Time**: 15-20 hours across all phases
**Expected ROI**: 75-85% reduction in API calls and tokens for typical workflows

---

*Design document v1.0 - November 9, 2025*
