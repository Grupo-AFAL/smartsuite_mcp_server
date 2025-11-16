# Caching Alternatives Analysis: API Call & Token Optimization

## Goal-Focused Evaluation

**Primary Goals:**
1. **Minimize API calls** to SmartSuite API
2. **Minimize context/tokens** consumed by the AI

---

## Alternative 1: In-Memory Cache (Ruby Hash/Objects)

### Description
Store cached data in Ruby instance variables (Hash, Array, custom objects). Similar to existing `@teams_cache` pattern.

```ruby
class CacheLayer
  def initialize
    @cache = {}  # Simple hash
    @ttl = {}    # Track expiration
  end

  def get(key)
    return nil if expired?(key)
    @cache[key]
  end

  def set(key, value, ttl:)
    @cache[key] = value
    @ttl[key] = Time.now + ttl
  end
end
```

### API Call Reduction: ⭐⭐⭐⭐ (4/5)
- ✅ Fast lookups (O(1) hash access)
- ✅ Eliminates duplicate API calls within session
- ❌ **Lost on restart** - cold start every session
- ❌ No cross-session benefit

**Typical Session:**
- First session: 22 API calls
- Subsequent calls in same session: 4 API calls (82% reduction)
- **Next session: Back to 22 API calls** (no persistence)

### Token Efficiency: ⭐⭐ (2/5)
- ❌ **Must send all data to AI** - no query capabilities
- ❌ Can't filter before sending to AI
- ✅ Can format before caching (use ResponseFormatter)
- ❌ No aggregation without sending full dataset

**Example:**
```ruby
# Find inactive solutions
cached_solutions = @cache.get('solutions')  # All 110 solutions
# Must send ALL 110 to AI to filter → ~16,500 tokens
```

### Pros:
- ✅ Simplest to implement (~50 lines)
- ✅ Fastest performance (memory speed)
- ✅ No dependencies
- ✅ Already partially implemented (@teams_cache)

### Cons:
- ❌ No persistence across sessions
- ❌ No query capabilities
- ❌ Can't reduce tokens for analytical queries
- ❌ Memory leaks if unbounded

### Implementation Time: 2-3 hours

---

## Alternative 2: SQLite Cache (Original Design)

### Description
Persistent database with both key-value cache and normalized queryable tables.

```ruby
# Dual-mode: Key-value + normalized tables
cache.get('solutions')  # Key-value retrieval
cache.query("SELECT * FROM solutions WHERE last_access < ?", cutoff)  # SQL query
```

### API Call Reduction: ⭐⭐⭐⭐⭐ (5/5)
- ✅ Persistent across sessions
- ✅ Accumulates knowledge over time
- ✅ Survives server restarts
- ✅ Warmup queries on startup possible

**Multi-Session:**
- Session 1: 22 API calls → cache populated
- Session 2: 2-4 API calls (90% reduction)
- Session 3+: 1-2 API calls (95% reduction)

### Token Efficiency: ⭐⭐⭐⭐⭐ (5/5)
- ✅ **SQL queries = massive token savings**
- ✅ Filter/aggregate before sending to AI
- ✅ Return only needed fields
- ✅ Pre-computed summaries

**Example:**
```ruby
# Find inactive solutions - query cache, return 5 results
inactive = cache.query("SELECT id, name FROM solutions WHERE last_access < ? LIMIT 5", cutoff)
# AI receives: 5 × 50 tokens = 250 tokens (vs 16,500 without query)
# 98.5% token reduction
```

### Pros:
- ✅ Best token reduction (98%+ for analytical queries)
- ✅ Persistent across sessions
- ✅ SQL query power
- ✅ Indexing for fast lookups
- ✅ Built-in to Ruby (stdlib, no gems needed)
- ✅ Single file deployment

### Cons:
- ❌ More complex to implement (~300 lines)
- ❌ Schema maintenance required
- ❌ Slightly slower than in-memory (~microseconds, negligible)
- ❌ File I/O overhead

### Implementation Time: 15-20 hours (all phases)

---

## Alternative 3: JSON File Cache

### Description
Store cache as JSON files in a directory structure. One file per cache key or category.

```ruby
# Structure:
~/.smartsuite_mcp_cache/
  solutions.json
  tables/
    abc123.json
    def456.json
  members.json
```

```ruby
def get(key)
  file_path = cache_path_for(key)
  return nil unless File.exist?(file_path)

  data = JSON.parse(File.read(file_path))
  return nil if expired?(data)

  data['value']
end
```

### API Call Reduction: ⭐⭐⭐⭐ (4/5)
- ✅ Persistent across sessions
- ✅ Simple file-based storage
- ✅ Human-readable for debugging
- ❌ Slower file I/O for many small reads

**Multi-Session:**
- Session 1: 22 API calls → files created
- Session 2+: 4-6 API calls (75% reduction)

### Token Efficiency: ⭐⭐ (2/5)
- ❌ **No query capabilities** - must load entire file
- ❌ Can't filter without parsing full JSON
- ✅ Can pre-format data before storing
- ❌ No aggregation without loading all data

**Example:**
```ruby
# Find inactive solutions
solutions = JSON.parse(File.read('solutions.json'))  # Load all 110
# Must parse and send to AI → still ~16,500 tokens
```

### Pros:
- ✅ Human-readable (debugging)
- ✅ Persistent across sessions
- ✅ No schema needed
- ✅ Easy backup (copy files)
- ✅ Moderate implementation complexity

### Cons:
- ❌ No query capabilities (token inefficient)
- ❌ File I/O overhead
- ❌ Must load entire files to query
- ❌ No indexing
- ❌ Race conditions if multiple processes

### Implementation Time: 6-8 hours

---

## Alternative 4: Hybrid In-Memory + File Persistence

### Description
Best of both worlds: Fast in-memory cache with periodic JSON file persistence.

```ruby
class HybridCache
  def initialize
    @memory_cache = {}  # Fast reads
    @file_path = '~/.smartsuite_mcp_cache.json'
    load_from_file  # Restore on startup
  end

  def get(key)
    @memory_cache[key]  # Fast memory lookup
  end

  def set(key, value, ttl:)
    @memory_cache[key] = {value: value, expires: Time.now + ttl}
    schedule_persist  # Async write to file
  end

  def persist
    File.write(@file_path, @memory_cache.to_json)
  end
end
```

### API Call Reduction: ⭐⭐⭐⭐ (4/5)
- ✅ Fast in-memory lookups
- ✅ Survives restarts (via file restore)
- ✅ Good session-to-session persistence
- ❌ Slight delay on startup (loading file)

**Multi-Session:**
- Session 1: 22 API calls → cache in memory + persisted
- Session 2+: 4-5 API calls (80% reduction)

### Token Efficiency: ⭐⭐ (2/5)
- ❌ **No query capabilities** (like in-memory)
- ❌ Must load full structures to filter
- ✅ Can pre-format before caching
- ❌ No SQL aggregation

**Example:**
```ruby
# Find inactive solutions
solutions = cache.get('solutions')  # All 110 in memory
# Still need to send all to AI → ~16,500 tokens
```

### Pros:
- ✅ Fast (memory speed)
- ✅ Persistent across sessions
- ✅ Moderate complexity
- ✅ No external dependencies

### Cons:
- ❌ No query capabilities (token inefficient)
- ❌ File writes can fail silently
- ❌ Race conditions if multiple processes
- ❌ Must keep everything in memory

### Implementation Time: 8-10 hours

---

## Alternative 5: "Smart Fetch" Strategy (No Cache, Better Queries)

### Description
Instead of caching, optimize the API calls and data filtering at the source.

```ruby
# Strategy: Always fetch minimal data from API
def list_solutions_for_analysis
  # Fetch with minimal fields only
  api_request('solutions/', fields: ['id', 'name', 'status', 'last_access'])
  # Returns ~50 tokens per solution instead of 150
end

# Strategy: Server-side filtering when possible
def get_inactive_solutions
  # Problem: SmartSuite API doesn't support server-side filtering for solutions
  # Must fetch all and filter client-side
end
```

### API Call Reduction: ⭐ (1/5)
- ❌ **No reduction** - every query hits API
- ❌ Repeated calls for same data
- ✅ Always fresh data (no staleness)
- ❌ Subject to rate limits

**Typical Session:**
- Every session: 22+ API calls
- No improvement over baseline

### Token Efficiency: ⭐⭐⭐ (3/5)
- ✅ Can request minimal fields from API
- ✅ Use ResponseFormatter aggressively
- ❌ Still must send full data to AI for filtering
- ❌ No pre-aggregation possible

**Example:**
```ruby
# Find inactive solutions
solutions = api_request('solutions/', fields: ['id', 'name', 'last_access'])
# Reduced to ~50 tokens per solution = 5,500 tokens (vs 16,500)
# But still must send all to AI to filter
```

### Pros:
- ✅ No caching complexity
- ✅ Always fresh data
- ✅ No persistence needed
- ✅ Simplest to maintain

### Cons:
- ❌ No API call reduction
- ❌ Moderate token inefficiency
- ❌ Subject to rate limits
- ❌ Slow (network latency every time)

### Implementation Time: 2-3 hours (enhance existing ResponseFormatter)

---

## Alternative 6: Semantic Cache (AI Embedding-Based)

### Description
Cache based on semantic similarity of queries rather than exact keys. Use embeddings to find similar questions.

```ruby
# Example:
# Query 1: "What solutions are inactive?"
# Query 2: "Show me solutions with no activity"
# → Same semantic meaning, reuse cached result
```

### API Call Reduction: ⭐⭐⭐ (3/5)
- ✅ Can reuse cache across similar queries
- ❌ Complex to implement correctly
- ❌ Requires embedding model (external dependency)
- ❌ Cold start on first query

### Token Efficiency: ⭐⭐ (2/5)
- ❌ Still must send full data to AI
- ❌ No query capabilities
- ✅ Can cache formatted responses
- ❌ Overhead of embedding computation

### Pros:
- ✅ Intelligent cache reuse
- ✅ User doesn't need exact keywords

### Cons:
- ❌ Very complex (~500+ lines)
- ❌ Requires embedding model (Ollama, OpenAI, etc.)
- ❌ External dependency
- ❌ No token reduction for analytical queries
- ❌ Overkill for this use case

### Implementation Time: 40+ hours

**Verdict: NOT RECOMMENDED** - Too complex for marginal benefit

---

## Alternative 7: Tiered Cache (Memory L1 + SQLite L2)

### Description
Two-layer cache: Fast in-memory L1 for hot data, SQLite L2 for persistence and queries.

```ruby
class TieredCache
  def initialize
    @l1_cache = {}  # Fast memory (LRU, max 100 entries)
    @l2_cache = SQLite3::Database.new('cache.db')  # Persistent query layer
  end

  def get(key)
    # Try L1 first
    return @l1_cache[key] if @l1_cache[key]

    # Fallback to L2 (SQLite)
    result = @l2_cache.execute("SELECT value FROM cache WHERE key = ?", key).first

    # Promote to L1
    @l1_cache[key] = result if result
    result
  end

  def query(sql)
    # Always query L2 (SQLite) for analytical queries
    @l2_cache.execute(sql)
  end
end
```

### API Call Reduction: ⭐⭐⭐⭐⭐ (5/5)
- ✅ L1 = maximum speed for hot data
- ✅ L2 = persistence across sessions
- ✅ Best of both approaches
- ✅ Warmup on startup from L2

**Multi-Session:**
- Session 1: 22 API calls → both L1 and L2 populated
- Session 2+: 1-2 API calls (95% reduction)
- Within session: ~0.5ms L1 hits, ~2ms L2 hits

### Token Efficiency: ⭐⭐⭐⭐⭐ (5/5)
- ✅ **SQL queries via L2** (98%+ token reduction)
- ✅ Fast retrieval via L1
- ✅ Pre-aggregation and filtering
- ✅ Return only needed fields

**Example:**
```ruby
# Hot path (repeated access)
solutions = cache.get('solutions')  # L1 hit, <1ms, 0 API calls

# Analytical query (token-efficient)
inactive = cache.query("SELECT id, name FROM solutions WHERE last_access < ?", cutoff)
# L2 query, 250 tokens vs 16,500 (98.5% reduction)
```

### Pros:
- ✅ Best API call reduction
- ✅ Best token efficiency
- ✅ Maximum performance
- ✅ Persistent + fast

### Cons:
- ❌ Most complex to implement (~400 lines)
- ❌ LRU eviction logic needed
- ❌ Cache coherency between L1/L2
- ❌ Memory management required

### Implementation Time: 20-25 hours

---

## Comparison Matrix

| Alternative | API Calls | Tokens | Complexity | Persistence | Query | Deployment | Score |
|-------------|-----------|--------|------------|-------------|-------|------------|-------|
| **1. In-Memory** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ❌ | ❌ | ⭐⭐⭐⭐⭐ | 18/30 |
| **2. SQLite** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ✅ | ✅ | ⭐⭐⭐⭐⭐ | 27/30 |
| **3. JSON Files** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ✅ | ❌ | ⭐⭐⭐⭐ | 19/30 |
| **4. Hybrid Mem+File** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ✅ | ❌ | ⭐⭐⭐⭐ | 19/30 |
| **5. No Cache** | ⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | N/A | ❌ | ⭐⭐⭐⭐⭐ | 16/30 |
| **6. Semantic** | ⭐⭐⭐ | ⭐⭐ | ⭐ | ✅ | ❌ | ⭐ | 10/30 |
| **7. Tiered L1/L2** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ✅ | ✅ | ⭐⭐⭐⭐ | 26/30 |

---

## Deep Dive: Token Optimization Comparison

### Scenario: "Find solutions not accessed in 90 days with >10 records"

#### Alternative 1 (In-Memory):
```ruby
solutions = @cache.get('solutions')  # All 110 solutions
# Must send to AI: 110 × 150 tokens = 16,500 tokens
# AI filters in context
```
**Result: 16,500 tokens**

#### Alternative 2 (SQLite):
```ruby
inactive = @cache.query(
  "SELECT id, name, last_access, records_count FROM solutions
   WHERE last_access < ? AND records_count > 10",
  cutoff
)
# Returns: 5 solutions × 50 tokens = 250 tokens
```
**Result: 250 tokens (98.5% reduction)**

#### Alternative 3 (JSON Files):
```ruby
solutions = JSON.parse(File.read('solutions.json'))  # All 110
# Must send to AI: 110 × 150 tokens = 16,500 tokens
```
**Result: 16,500 tokens**

#### Alternative 4 (Hybrid):
```ruby
solutions = @cache.get('solutions')  # From memory/file
# Must send to AI: 110 × 150 tokens = 16,500 tokens
```
**Result: 16,500 tokens**

#### Alternative 5 (No Cache):
```ruby
solutions = api_request('solutions/', fields: ['id', 'name', 'last_access', 'records_count'])
# Must send to AI: 110 × 50 tokens = 5,500 tokens
```
**Result: 5,500 tokens (better than some cached approaches!)**

#### Alternative 7 (Tiered):
```ruby
inactive = @cache.query(  # L2 SQLite query
  "SELECT id, name FROM solutions
   WHERE last_access < ? AND records_count > 10 LIMIT 5",
  cutoff
)
# Returns: 5 solutions × 50 tokens = 250 tokens
```
**Result: 250 tokens (98.5% reduction)**

### Winner: SQLite (#2) and Tiered (#7)

---

## Deep Dive: API Call Optimization Comparison

### Scenario: User explores SmartSuite workspace over 3 sessions

#### Alternative 1 (In-Memory):
```
Session 1: 22 API calls (cache miss on start)
Session 2: 22 API calls (cache lost, restart)
Session 3: 22 API calls (cache lost, restart)
Total: 66 API calls
```

#### Alternative 2 (SQLite):
```
Session 1: 22 API calls (populate cache)
Session 2: 2 API calls (cache hit 90%)
Session 3: 1 API call (cache hit 95%)
Total: 25 API calls (62% reduction)
```

#### Alternative 3 (JSON Files):
```
Session 1: 22 API calls (populate files)
Session 2: 4 API calls (file read, some misses)
Session 3: 3 API calls (mostly hits)
Total: 29 API calls (56% reduction)
```

#### Alternative 4 (Hybrid):
```
Session 1: 22 API calls (populate cache + files)
Session 2: 3 API calls (restore from files, some misses)
Session 3: 2 API calls (memory + files)
Total: 27 API calls (59% reduction)
```

#### Alternative 5 (No Cache):
```
Session 1: 22 API calls
Session 2: 22 API calls
Session 3: 22 API calls
Total: 66 API calls (0% reduction)
```

#### Alternative 7 (Tiered):
```
Session 1: 22 API calls (populate L1 + L2)
Session 2: 1 API call (L1 miss, L2 hit)
Session 3: 0 API calls (all L1 hits)
Total: 23 API calls (65% reduction)
```

### Winner: Tiered (#7) slightly beats SQLite (#2)

---

## Recommendation Tiers

### 🥇 BEST FOR YOUR GOALS: SQLite Cache (Alternative 2)

**Why:**
- ✅ **98.5% token reduction** for analytical queries (your #2 goal)
- ✅ **62% API call reduction** across sessions (your #1 goal)
- ✅ Best balance of performance vs complexity
- ✅ Single-file deployment (easy)
- ✅ SQL queries enable massive token savings
- ✅ No external dependencies (stdlib only)

**Trade-off:** 15-20 hours implementation time

**Best for:** Production use, long-term efficiency, analytical workloads

---

### 🥈 RUNNER-UP: Tiered L1/L2 Cache (Alternative 7)

**Why:**
- ✅ **98.5% token reduction** (same as SQLite)
- ✅ **65% API call reduction** (best)
- ✅ Fastest performance (memory L1)
- ✅ Maximum optimization

**Trade-off:** 20-25 hours implementation, higher complexity

**Best for:** Maximum performance, high-frequency usage, production with dedicated maintenance

---

### 🥉 QUICK WIN: In-Memory Cache (Alternative 1)

**Why:**
- ✅ **82% API call reduction** within session
- ✅ Simplest to implement (2-3 hours)
- ✅ Extends existing @teams_cache pattern
- ❌ **No token optimization** for analytical queries
- ❌ Lost on restart

**Best for:** Quick proof-of-concept, MVP, short-term improvement

---

### ❌ NOT RECOMMENDED:
- Alternative 3 (JSON Files) - Complexity without query benefits
- Alternative 4 (Hybrid) - Complexity without token benefits
- Alternative 5 (No Cache) - Misses both goals
- Alternative 6 (Semantic) - Overkill and complex

---

## Novel Idea: Preprocessed Summaries Cache

### Concept
Instead of caching raw data, cache **pre-computed summaries** optimized for AI consumption.

```ruby
# Instead of caching raw solutions list:
@cache['solutions'] = [110 solution objects]  # 16,500 tokens

# Cache pre-computed summaries:
@cache['solutions:summary'] = {
  total: 110,
  by_status: {active: 85, archived: 20, hidden: 5},
  inactive_90d: [{id: 'sol_1', name: 'Old Solution', days: 120}, ...],
  top_by_records: [{id: 'sol_2', name: 'Big Solution', records: 5000}, ...]
}  # 500 tokens

# Cache denormalized queryable index:
@cache['solutions:by_owner:user_123'] = ['sol_1', 'sol_5', 'sol_12']
@cache['solutions:inactive'] = ['sol_3', 'sol_8']
```

### Implementation with SQLite
```sql
-- Pre-compute summary views
CREATE VIEW solution_summary AS
SELECT
  status,
  COUNT(*) as count,
  AVG(records_count) as avg_records,
  SUM(CASE WHEN last_access < ? THEN 1 ELSE 0 END) as inactive_count
FROM solutions
GROUP BY status;

-- Index by common filters
CREATE INDEX idx_solutions_inactive ON solutions(last_access)
WHERE last_access < strftime('%s', 'now', '-90 days');
```

### Benefits
- ✅ **99%+ token reduction** for common queries
- ✅ AI receives pre-digested data
- ✅ Combines with SQLite design
- ✅ Cache what AI needs, not raw API responses

### Example
```ruby
# User asks: "What's the status of my workspace?"
summary = cache.get_solution_summary
# Returns: {total: 110, active: 85, inactive: 15, top_5: [...]}
# AI receives: 300 tokens instead of 16,500 (98.2% reduction)
```

---

## Final Recommendation

### For Maximum Efficiency on Both Goals:

**Implement: SQLite Cache + Preprocessed Summaries**

**Phase 1 (4-6 hours):**
- Core SQLite cache (key-value + normalized tables)
- Basic get/set/invalidate

**Phase 2 (5-7 hours):**
- Integrate with API operations
- Add common queries

**Phase 3 (3-4 hours):**
- Add preprocessed summary cache
- Create summary views and indexes
- Add MCP tools for summary access

**Total: 12-17 hours for 98%+ optimization**

### Alternative Quick Start:

**Implement: In-Memory Cache (2-3 hours)**
- Immediate 82% API call reduction within sessions
- Extend to SQLite later when proven valuable

---

## Decision Matrix

Choose based on priorities:

| Priority | Recommendation |
|----------|---------------|
| **Maximum token savings** | SQLite (#2) or Tiered (#7) |
| **Maximum API reduction** | Tiered (#7) |
| **Best balance** | SQLite (#2) |
| **Fastest to implement** | In-Memory (#1) |
| **Simplest maintenance** | In-Memory (#1) or SQLite (#2) |
| **Future-proof** | SQLite (#2) |

**My recommendation: Start with SQLite (#2)**
- Best alignment with both goals
- Single-file deployment (your requirement)
- Queryable cache (your requirement)
- Proven technology
- Reasonable implementation time
