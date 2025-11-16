# SQLite Caching Layer: Deep Dive Design Document

## Overview

This document addresses three critical design decisions for the SQLite caching implementation:

1. **ORM vs Raw SQLite** - Should we use ActiveRecord, Sequel, ROM, or raw SQLite3?
2. **Aggressive Fetch Strategy** - How to maximize data fetched per API call to minimize total requests
3. **Record Field Mapping & Filtering** - How to store dynamic record fields and enable efficient filtering

---

## 1. ORM Evaluation: ActiveRecord vs Sequel vs ROM vs Raw SQLite

### Option A: ActiveRecord

**Description:**
Ruby on Rails' ORM, most popular and feature-rich.

```ruby
# Example usage
gem 'activerecord'

class Solution < ActiveRecord::Base
  has_many :tables

  scope :inactive, ->(days) { where('last_access < ?', Time.now - days.days) }
end

# Query
inactive_solutions = Solution.inactive(90).where('records_count > ?', 10)
```

#### Pros:
- ✅ Most mature and battle-tested
- ✅ Excellent documentation and community
- ✅ Rich query DSL (scopes, associations, validations)
- ✅ Migration system built-in
- ✅ Familiar to most Ruby developers
- ✅ Automatic timestamps (created_at, updated_at)
- ✅ Callbacks for cache invalidation hooks

#### Cons:
- ❌ **Heavy dependency** - Pulls in ~10 gems (activesupport, activemodel, etc.)
- ❌ **Large footprint** - ~5MB+ of dependencies
- ❌ Designed for Rails ecosystem (overkill for MCP server)
- ❌ Slower than lighter alternatives (~10-20% overhead)
- ❌ Convention-heavy (magic methods, implicit behavior)

#### Metrics:
```
Dependency gems: 10+ (activerecord, activesupport, activemodel, etc.)
Total size: ~5-6 MB
Startup time: ~100-150ms additional
Query overhead: ~10-20% vs raw SQL
```

#### Verdict: ❌ **NOT RECOMMENDED**
Too heavy for a lightweight MCP server. We're not building a Rails app.

---

### Option B: Sequel

**Description:**
Lightweight, flexible database toolkit for Ruby. Called "the database toolkit for Ruby."

```ruby
# Example usage
gem 'sequel'

DB = Sequel.sqlite('cache.db')

class Solution < Sequel::Model
  one_to_many :tables

  dataset_module do
    def inactive(days)
      where(Sequel.lit('last_access < ?', Time.now.to_i - days * 86400))
    end
  end
end

# Query
inactive = Solution.inactive(90).where { records_count > 10 }
```

#### Pros:
- ✅ **Lightweight** - Single gem, minimal dependencies
- ✅ **Fast** - Closer to raw SQL performance (~5% overhead)
- ✅ Excellent SQL generation and query DSL
- ✅ Built-in migration system
- ✅ Thread-safe connection pooling
- ✅ Supports both models and datasets (flexible)
- ✅ Great for standalone apps (not Rails-specific)
- ✅ Better documentation than ROM

#### Cons:
- ❌ Still a dependency (external gem required)
- ❌ Learning curve for team unfamiliar with it
- ❌ Less common than ActiveRecord (smaller community)
- ❌ Model layer may be overkill for simple caching

#### Metrics:
```
Dependency gems: 1 (sequel)
Total size: ~800 KB
Startup time: ~20-30ms additional
Query overhead: ~5% vs raw SQL
```

#### Verdict: 🟡 **GOOD OPTION**
Best ORM choice if we want one. Lightweight and performant.

---

### Option C: ROM (Ruby Object Mapper)

**Description:**
Modern data mapping toolkit with functional approach.

```ruby
# Example usage
gem 'rom'
gem 'rom-sql'

class Solutions < ROM::Relation[:sql]
  schema(:solutions, infer: true)

  def inactive(days)
    where { last_access < (Time.now.to_i - days * 86400) }
  end
end

# Query
rom.relations[:solutions].inactive(90).where { records_count > 10 }
```

#### Pros:
- ✅ Modern, functional design
- ✅ Separation of concerns (relations, mappers, commands)
- ✅ Good performance
- ✅ Flexible architecture

#### Cons:
- ❌ **Steep learning curve** - Very different from traditional ORMs
- ❌ Less documentation and examples
- ❌ Smaller community
- ❌ More boilerplate for simple use cases
- ❌ Multiple gems required (rom, rom-sql, etc.)
- ❌ Overkill for caching layer

#### Metrics:
```
Dependency gems: 3+ (rom, rom-sql, rom-core)
Total size: ~1-2 MB
Startup time: ~30-50ms additional
Query overhead: ~5-10% vs raw SQL
```

#### Verdict: ❌ **NOT RECOMMENDED**
Too complex for our use case. Better suited for complex domain models.

---

### Option D: Raw SQLite3 (Ruby stdlib)

**Description:**
Direct usage of Ruby's built-in SQLite3 library.

```ruby
# Example usage (no gems needed)
require 'sqlite3'

db = SQLite3::Database.new('cache.db')
db.results_as_hash = true

# Create table
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS solutions (
    id TEXT PRIMARY KEY,
    name TEXT,
    last_access INTEGER,
    records_count INTEGER
  )
SQL

# Query
inactive = db.execute(
  "SELECT * FROM solutions WHERE last_access < ? AND records_count > ?",
  Time.now.to_i - 90*86400,
  10
)
```

#### Pros:
- ✅ **Zero dependencies** - Built into Ruby stdlib
- ✅ **Fastest** - No ORM overhead
- ✅ **Full control** - Write exact SQL you need
- ✅ **Simplest deployment** - No gem installation
- ✅ **Lightweight** - Minimal memory footprint
- ✅ **Transparent** - No magic, what you see is what you get
- ✅ Perfect for MCP server use case

#### Cons:
- ❌ More verbose than ORM DSL
- ❌ Manual schema management (write own migrations)
- ❌ No built-in associations or validations
- ❌ More SQL writing required
- ❌ Potential for SQL injection if not careful (use parameterized queries)

#### Metrics:
```
Dependency gems: 0 (stdlib)
Total size: 0 KB additional
Startup time: ~0ms additional
Query overhead: 0% (pure SQL)
```

#### Verdict: ✅ **RECOMMENDED**
Perfect fit for our lightweight MCP server. No dependencies, maximum performance.

---

### ORM Comparison Matrix

| Feature | ActiveRecord | Sequel | ROM | Raw SQLite3 |
|---------|-------------|--------|-----|-------------|
| **Dependencies** | ❌ 10+ gems | 🟡 1 gem | 🟡 3+ gems | ✅ 0 gems |
| **Size** | ❌ ~5-6 MB | ✅ ~800 KB | 🟡 ~1-2 MB | ✅ 0 KB |
| **Performance** | 🟡 -20% | ✅ -5% | ✅ -5-10% | ✅ 100% |
| **Learning Curve** | ✅ Easy | 🟡 Moderate | ❌ Steep | ✅ Easy |
| **Query DSL** | ✅ Excellent | ✅ Excellent | 🟡 Good | ❌ Raw SQL |
| **Migrations** | ✅ Built-in | ✅ Built-in | 🟡 Separate | ❌ Manual |
| **Documentation** | ✅ Excellent | ✅ Good | 🟡 Moderate | ✅ Excellent |
| **Deployment** | ❌ Complex | 🟡 Simple | 🟡 Simple | ✅ Trivial |
| **Use Case Fit** | ❌ Overkill | 🟡 Good | ❌ Overcomplicated | ✅ Perfect |

**Score:**
- ActiveRecord: 4/9 ❌
- Sequel: 7/9 🟡
- ROM: 4/9 ❌
- **Raw SQLite3: 8/9** ✅

---

### Recommendation: Raw SQLite3 with Helper Methods

**Strategy:** Use raw SQLite3 but create a thin abstraction layer for common patterns.

```ruby
# lib/smartsuite/cache_layer.rb

module SmartSuite
  class CacheLayer
    def initialize(db_path: nil)
      @db_path = db_path || File.expand_path('~/.smartsuite_mcp_cache.db')
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true
      setup_schema
    end

    # Generic cache operations
    def get(key)
      row = @db.execute(
        "SELECT value, expires_at FROM cache_entries WHERE key = ? AND expires_at > ?",
        key, Time.now.to_i
      ).first

      return nil unless row
      JSON.parse(row['value'])
    end

    def set(key, value, ttl:, category: 'generic')
      @db.execute(
        "INSERT OR REPLACE INTO cache_entries (key, value, created_at, expires_at, category)
         VALUES (?, ?, ?, ?, ?)",
        key, value.to_json, Time.now.to_i, Time.now.to_i + ttl, category
      )
    end

    # High-level query methods (abstraction layer)
    def find_solutions(filters = {})
      query = "SELECT * FROM solutions WHERE 1=1"
      params = []

      if filters[:status]
        query += " AND status = ?"
        params << filters[:status]
      end

      if filters[:inactive_days]
        query += " AND last_access < ?"
        params << (Time.now.to_i - filters[:inactive_days] * 86400)
      end

      if filters[:min_records]
        query += " AND records_count >= ?"
        params << filters[:min_records]
      end

      @db.execute(query, params)
    end

    def find_tables_by_solution(solution_id)
      @db.execute("SELECT * FROM tables WHERE solution_id = ?", solution_id)
    end

    def find_fields_by_type(field_type, table_ids: nil)
      if table_ids
        placeholders = table_ids.map { '?' }.join(',')
        @db.execute(
          "SELECT * FROM fields WHERE field_type = ? AND table_id IN (#{placeholders})",
          field_type, *table_ids
        )
      else
        @db.execute("SELECT * FROM fields WHERE field_type = ?", field_type)
      end
    end

    private

    def setup_schema
      # Migration-style schema setup
      @db.execute_batch <<-SQL
        CREATE TABLE IF NOT EXISTS cache_entries (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          category TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_expires_at ON cache_entries(expires_at);
        CREATE INDEX IF NOT EXISTS idx_category ON cache_entries(category);

        -- More tables...
      SQL
    end
  end
end
```

**Benefits:**
- ✅ Zero dependencies
- ✅ Maximum performance
- ✅ Simple deployment
- ✅ High-level methods for common queries
- ✅ Raw SQL available when needed
- ✅ Easy to understand and maintain

---

## 2. Aggressive Fetch Strategy: Maximize Data per Request

### Principle: "Fetch Once, Query Many"

Instead of fetching minimal data, we should:
1. **Fetch as much data as possible** in each API request
2. **Store everything in the database**
3. **Query the database** for exactly what we need
4. **Result:** Fewer total API requests, more efficient token usage

### Example: Current vs Aggressive Strategy

#### Current Approach (Conservative Fetching):
```ruby
# User asks: "What solutions are inactive?"

# Call 1: Fetch minimal solution data
solutions = api_request('solutions/', fields: ['id', 'name', 'last_access'])

# Later, user asks: "What's the status of inactive solutions?"
# Call 2: Fetch again with status field
solutions = api_request('solutions/', fields: ['id', 'name', 'last_access', 'status'])

# Later, user asks: "How many records in each?"
# Call 3: Fetch again with records_count
solutions = api_request('solutions/', fields: ['id', 'name', 'last_access', 'status', 'records_count'])

# Total: 3 API calls, 3 × network latency
```

#### Aggressive Approach:
```ruby
# User asks: "What solutions are inactive?"

# Call 1: Fetch ALL available solution data
solutions = api_request('solutions/')  # No field filtering
# Store in DB: id, name, status, last_access, records_count, members_count,
#              automations_count, permissions, etc.

# Later, user asks: "What's the status?"
result = cache.query("SELECT id, name, status FROM solutions WHERE last_access < ?", cutoff)
# No API call needed!

# Later, user asks: "How many records?"
result = cache.query("SELECT id, name, records_count FROM solutions WHERE last_access < ?", cutoff)
# No API call needed!

# Total: 1 API call initially, then all queries from cache
```

### Strategy Implementation

#### 1. Never Request Specific Fields from API

```ruby
# ❌ Don't do this:
def list_solutions(fields: nil)
  query_params = {}
  query_params[:fields] = fields if fields
  api_request('solutions/', query_params: query_params)
end

# ✅ Do this:
def list_solutions
  # Always fetch everything, ignore fields parameter from user
  result = api_request('solutions/')  # Full response

  # Store everything in cache
  cache.upsert_solutions(result)

  # Return full result (will be filtered later if needed)
  result
end
```

#### 2. Fetch Related Data Proactively

```ruby
# When user fetches a solution, also fetch its tables
def get_solution(solution_id)
  # Fetch solution
  solution = api_request("solutions/#{solution_id}/")
  cache.upsert_solution(solution)

  # ALSO fetch all tables in this solution (proactive)
  if solution['applications_count'] > 0 && solution['applications_count'] < 50
    tables = api_request("applications/", query_params: {solution: solution_id})
    cache.upsert_tables(tables)
  end

  solution
end

# When user fetches a table, also fetch its structure
def list_tables(solution_id:)
  tables = api_request("applications/", query_params: {solution: solution_id})

  # ALSO fetch structure for each table (if not too many)
  if tables.size <= 10
    tables.each do |table|
      structure = api_request("applications/#{table['id']}/")
      cache.upsert_table_structure(table['id'], structure)
    end
  end

  tables
end
```

#### 3. Background Cache Warming

```ruby
# On server initialization, warm cache with common data
class SmartSuiteServer
  def initialize
    @client = SmartSuiteClient.new(...)

    # Warm cache in background thread (non-blocking)
    Thread.new do
      warm_cache
    end
  end

  private

  def warm_cache
    # Fetch solutions (most commonly queried)
    @client.list_solutions

    # Fetch members (frequently needed)
    @client.list_members

    # Fetch teams
    @client.list_teams

    log_metric("Cache warmed with solutions, members, and teams")
  rescue => e
    # Silent failure - cache warming is opportunistic
    log_error("Cache warming failed: #{e.message}")
  end
end
```

#### 4. Incremental Cache Building

```ruby
# Track what we've fetched to avoid redundant calls
def get_table_structure(table_id)
  # Check cache first
  cached = cache.get_table(table_id)

  if cached
    # Check if we have full structure or just metadata
    if cached['structure']
      return cached  # We have everything
    else
      # We only have metadata, fetch full structure
      full = api_request("applications/#{table_id}/")
      cache.upsert_table_structure(table_id, full)
      return full
    end
  end

  # Not in cache at all, fetch
  full = api_request("applications/#{table_id}/")
  cache.upsert_table_structure(table_id, full)
  full
end
```

### Trade-offs of Aggressive Fetching

#### Pros:
- ✅ **Dramatically fewer API calls** (80-90% reduction)
- ✅ Cache becomes comprehensive quickly
- ✅ Anticipates future queries
- ✅ Better user experience (instant responses after first fetch)
- ✅ Maximizes value of each API call

#### Cons:
- ❌ Initial API calls are slower (more data transferred)
- ❌ More data stored in database (larger DB file)
- ❌ May fetch data that's never used
- ❌ Higher memory usage during processing

#### Mitigation Strategies:

**1. Smart Thresholds**
```ruby
# Don't fetch ALL tables if there are 100+
if solution['applications_count'] < 50
  fetch_all_tables(solution_id)
else
  # Wait for user to request specific tables
end
```

**2. Prioritize Common Queries**
```ruby
# Always fetch: solutions, members, teams (commonly queried)
# Sometimes fetch: tables (if solution has <50)
# Lazy fetch: individual records (high volume, low reuse)
```

**3. Monitor Cache Hit Rates**
```ruby
# Track what gets used
cache_stats = cache.get_stats

if cache_stats[:tables_hit_rate] < 0.3  # Less than 30% hit rate
  # We're over-fetching tables, reduce proactive fetching
  @proactive_table_fetch_threshold = 10
end
```

### Recommended Aggressive Fetch Rules

| Data Type | Fetch Strategy | Rationale |
|-----------|---------------|-----------|
| **Solutions** | ✅ Always full | Small dataset (~110), high reuse |
| **Members** | ✅ Always full | Medium dataset (~1000), high reuse |
| **Teams** | ✅ Always full | Small dataset (~50), high reuse |
| **Tables (list)** | ✅ Always full | Per-solution fetch, high reuse |
| **Table structure** | 🟡 Conditional | If <20 tables in solution |
| **Records** | ❌ Lazy | Large dataset, low reuse, high mutation |
| **Comments** | ❌ Lazy | Per-record, low reuse, high mutation |

---

## 3. Record Field Mapping & Filtering

### Challenge: Dynamic Schema

SmartSuite records have **dynamic fields** based on table structure:

```json
// Table A has these fields:
{
  "title": "Project Alpha",
  "status": "Active",
  "assigned_to": ["user_123"]
}

// Table B has completely different fields:
{
  "customer_name": "ACME Corp",
  "revenue": 50000,
  "contract_date": "2025-01-01"
}
```

**Problem:** How do we store and query records with different schemas in SQLite?

### Approach 1: JSON Blob Storage (Recommended for MVP)

#### Schema Design:
```sql
CREATE TABLE records (
  id TEXT PRIMARY KEY,
  table_id TEXT NOT NULL,
  title TEXT,              -- Primary field (denormalized for speed)
  data TEXT NOT NULL,      -- JSON blob with all fields
  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
);

CREATE INDEX idx_records_table ON records(table_id);
CREATE INDEX idx_records_title ON records(title);
CREATE INDEX idx_records_expires ON records(expires_at);
```

#### Storage:
```ruby
def cache_record(table_id, record)
  # Extract primary field (title)
  table_structure = get_table_structure(table_id)
  primary_field = table_structure['structure'].find { |f| f['primary'] }
  title = record[primary_field['slug']] if primary_field

  @db.execute(
    "INSERT OR REPLACE INTO records (id, table_id, title, data, created_on, updated_on, cached_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    record['id'],
    table_id,
    title,
    record.to_json,  # Store everything as JSON
    record['created_on'],
    record['updated_on'],
    Time.now.to_i,
    Time.now.to_i + 300  # 5 minute TTL
  )
end
```

#### Querying with JSON Functions:
```ruby
# SQLite supports JSON path queries
def find_records_by_status(table_id, status)
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ?
     AND json_extract(data, '$.status') = ?",
    table_id, status
  )
end

def find_records_by_assigned_user(table_id, user_id)
  # Search JSON array
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ?
     AND EXISTS (
       SELECT 1 FROM json_each(json_extract(data, '$.assigned_to'))
       WHERE value = ?
     )",
    table_id, user_id
  )
end

def find_records_by_numeric_range(table_id, field_slug, min, max)
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ?
     AND CAST(json_extract(data, '$.' || ?) AS REAL) BETWEEN ? AND ?",
    table_id, field_slug, min, max
  )
end
```

#### Pros:
- ✅ Simple schema (one table for all records)
- ✅ No schema migration when fields change
- ✅ Stores complete record data
- ✅ SQLite JSON functions are powerful

#### Cons:
- ❌ Slower queries on JSON fields vs indexed columns
- ❌ Can't create indexes on JSON properties (in SQLite <3.38)
- ❌ Type conversion required (everything is text in JSON)

---

### Approach 2: EAV (Entity-Attribute-Value) Pattern

#### Schema Design:
```sql
CREATE TABLE records (
  id TEXT PRIMARY KEY,
  table_id TEXT NOT NULL,
  title TEXT,
  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
);

CREATE TABLE record_values (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  record_id TEXT NOT NULL,
  field_slug TEXT NOT NULL,
  value_type TEXT NOT NULL,  -- 'string', 'number', 'array', 'date'
  value_text TEXT,
  value_number REAL,
  value_date INTEGER,
  value_json TEXT,           -- For arrays and objects
  UNIQUE(record_id, field_slug),
  FOREIGN KEY (record_id) REFERENCES records(id) ON DELETE CASCADE
);

CREATE INDEX idx_record_values_record ON record_values(record_id);
CREATE INDEX idx_record_values_field ON record_values(field_slug);
CREATE INDEX idx_record_values_text ON record_values(value_text);
CREATE INDEX idx_record_values_number ON record_values(value_number);
CREATE INDEX idx_record_values_date ON record_values(value_date);
```

#### Storage:
```ruby
def cache_record_eav(table_id, record)
  # Insert record metadata
  @db.execute(
    "INSERT OR REPLACE INTO records (id, table_id, title, created_on, updated_on, cached_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    record['id'], table_id, record['title'], record['created_on'], record['updated_on'],
    Time.now.to_i, Time.now.to_i + 300
  )

  # Get table structure to know field types
  table_structure = get_table_structure(table_id)
  field_types = table_structure['structure'].map { |f| [f['slug'], f['field_type']] }.to_h

  # Insert each field value
  record.each do |field_slug, value|
    next if ['id', 'created_on', 'updated_on'].include?(field_slug)

    field_type = field_types[field_slug]
    store_value_eav(record['id'], field_slug, value, field_type)
  end
end

def store_value_eav(record_id, field_slug, value, field_type)
  case field_type
  when 'textfield', 'emailfield', 'phonefield'
    @db.execute(
      "INSERT OR REPLACE INTO record_values (record_id, field_slug, value_type, value_text)
       VALUES (?, ?, 'string', ?)",
      record_id, field_slug, value
    )
  when 'numberfield', 'currencyfield', 'percentfield'
    @db.execute(
      "INSERT OR REPLACE INTO record_values (record_id, field_slug, value_type, value_number)
       VALUES (?, ?, 'number', ?)",
      record_id, field_slug, value.to_f
    )
  when 'datefield', 'duedatefield'
    @db.execute(
      "INSERT OR REPLACE INTO record_values (record_id, field_slug, value_type, value_date)
       VALUES (?, ?, 'date', ?)",
      record_id, field_slug, parse_date(value)
    )
  when 'assignedtofield', 'linkedrecordfield', 'multipleselectfield'
    # Arrays stored as JSON
    @db.execute(
      "INSERT OR REPLACE INTO record_values (record_id, field_slug, value_type, value_json)
       VALUES (?, ?, 'array', ?)",
      record_id, field_slug, value.to_json
    )
  else
    # Unknown type, store as JSON
    @db.execute(
      "INSERT OR REPLACE INTO record_values (record_id, field_slug, value_type, value_json)
       VALUES (?, ?, 'unknown', ?)",
      record_id, field_slug, value.to_json
    )
  end
end
```

#### Querying:
```ruby
def find_records_by_status_eav(table_id, status)
  @db.execute(
    "SELECT r.id, r.title FROM records r
     JOIN record_values rv ON rv.record_id = r.id
     WHERE r.table_id = ?
     AND rv.field_slug = 'status'
     AND rv.value_text = ?",
    table_id, status
  )
end

def find_records_by_numeric_range_eav(table_id, field_slug, min, max)
  @db.execute(
    "SELECT r.id, r.title FROM records r
     JOIN record_values rv ON rv.record_id = r.id
     WHERE r.table_id = ?
     AND rv.field_slug = ?
     AND rv.value_number BETWEEN ? AND ?",
    table_id, field_slug, min, max
  )
end

def find_records_by_assigned_user_eav(table_id, user_id)
  @db.execute(
    "SELECT r.id, r.title FROM records r
     JOIN record_values rv ON rv.record_id = r.id
     WHERE r.table_id = ?
     AND rv.field_slug = 'assigned_to'
     AND json_extract(rv.value_json, '$') LIKE ?",
    table_id, "%#{user_id}%"
  )
end
```

#### Pros:
- ✅ Can index by value type (fast numeric/date queries)
- ✅ Normalized structure
- ✅ Proper SQL queries (no JSON parsing)
- ✅ Type-safe comparisons

#### Cons:
- ❌ Complex schema (2 tables per record)
- ❌ More storage overhead
- ❌ Joins required for every query
- ❌ More complex to implement

---

### Approach 3: Hybrid (Recommended for Production)

**Strategy:** Combine JSON blob with selective denormalization of commonly-queried fields.

#### Schema Design:
```sql
CREATE TABLE records (
  id TEXT PRIMARY KEY,
  table_id TEXT NOT NULL,
  title TEXT,                    -- Primary field (always denormalized)

  -- Commonly-filtered fields (denormalized for speed)
  status TEXT,                   -- For status filters
  assigned_to TEXT,              -- JSON array for user queries
  due_date INTEGER,              -- For date range queries

  -- Full data as JSON
  data TEXT NOT NULL,            -- Complete record

  -- Metadata
  created_on INTEGER,
  updated_on INTEGER,
  cached_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,

  FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
);

CREATE INDEX idx_records_table ON records(table_id);
CREATE INDEX idx_records_status ON records(status);
CREATE INDEX idx_records_due_date ON records(due_date);
CREATE INDEX idx_records_title ON records(title);
```

#### Storage:
```ruby
def cache_record_hybrid(table_id, record)
  # Extract commonly-queried fields
  status = extract_status_field(table_id, record)
  assigned_to = extract_assigned_to_field(table_id, record)
  due_date = extract_due_date_field(table_id, record)

  @db.execute(
    "INSERT OR REPLACE INTO records
     (id, table_id, title, status, assigned_to, due_date, data, created_on, updated_on, cached_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    record['id'],
    table_id,
    record['title'],
    status,
    assigned_to&.to_json,
    due_date,
    record.to_json,
    record['created_on'],
    record['updated_on'],
    Time.now.to_i,
    Time.now.to_i + 300
  )
end

def extract_status_field(table_id, record)
  # Find status/single-select field in table structure
  table = get_table_structure(table_id)
  status_field = table['structure'].find do |f|
    f['field_type'] == 'statusfield' || f['field_type'] == 'singleselectfield'
  end

  record[status_field['slug']] if status_field
end
```

#### Querying (Fast Path):
```ruby
# Common queries use indexed columns (fast)
def find_records_by_status_hybrid(table_id, status)
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ? AND status = ?",
    table_id, status
  )
end

def find_records_by_due_date_hybrid(table_id, start_date, end_date)
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ? AND due_date BETWEEN ? AND ?",
    table_id, start_date, end_date
  )
end

# Less common queries use JSON (slower but flexible)
def find_records_by_custom_field_hybrid(table_id, field_slug, value)
  @db.execute(
    "SELECT id, title, data FROM records
     WHERE table_id = ?
     AND json_extract(data, '$.' || ?) = ?",
    table_id, field_slug, value
  )
end
```

#### Pros:
- ✅ Fast queries for common patterns (indexed columns)
- ✅ Flexible queries for everything else (JSON)
- ✅ Best of both approaches
- ✅ Moderate complexity

#### Cons:
- ❌ Need to identify "common" fields
- ❌ Slight duplication (data in both column and JSON)
- ❌ More complex cache logic

---

## Filtering Strategy: Translating SmartSuite Filters to SQL

### Challenge: SmartSuite API Filter Format

SmartSuite uses a specific filter format:

```json
{
  "filter": {
    "operator": "and",
    "fields": [
      {
        "field": "status",
        "comparison": "is",
        "value": "Active"
      },
      {
        "field": "due_date",
        "comparison": "is_on_or_after",
        "value": {
          "date_mode": "exact_date",
          "date_mode_value": "2025-01-01"
        }
      }
    ]
  }
}
```

**Goal:** Translate this to SQL queries against our cache.

### Filter Translation Layer

```ruby
class FilterTranslator
  def initialize(table_id, cache)
    @table_id = table_id
    @cache = cache
    @table_structure = cache.get_table_structure(table_id)
  end

  def translate_to_sql(smartsuite_filter)
    return ["1=1", []] if smartsuite_filter.nil? || smartsuite_filter.empty?

    operator = smartsuite_filter['operator'] || 'and'
    fields = smartsuite_filter['fields'] || []

    conditions = []
    params = []

    fields.each do |field_filter|
      condition, field_params = translate_field_filter(field_filter)
      conditions << condition
      params.concat(field_params)
    end

    sql_operator = operator == 'and' ? ' AND ' : ' OR '
    where_clause = conditions.join(sql_operator)

    [where_clause, params]
  end

  private

  def translate_field_filter(field_filter)
    field_slug = field_filter['field']
    comparison = field_filter['comparison']
    value = field_filter['value']

    # Get field type from table structure
    field_info = @table_structure['structure'].find { |f| f['slug'] == field_slug }
    field_type = field_info['field_type']

    case field_type
    when 'textfield', 'emailfield', 'phonefield'
      translate_text_filter(field_slug, comparison, value)
    when 'numberfield', 'currencyfield', 'percentfield'
      translate_numeric_filter(field_slug, comparison, value)
    when 'datefield', 'duedatefield'
      translate_date_filter(field_slug, comparison, value)
    when 'statusfield', 'singleselectfield'
      translate_select_filter(field_slug, comparison, value)
    when 'assignedtofield', 'linkedrecordfield'
      translate_array_filter(field_slug, comparison, value)
    else
      # Fallback to JSON query
      translate_json_filter(field_slug, comparison, value)
    end
  end

  def translate_text_filter(field_slug, comparison, value)
    case comparison
    when 'is'
      ["json_extract(data, '$.#{field_slug}') = ?", [value]]
    when 'is_not'
      ["json_extract(data, '$.#{field_slug}') != ?", [value]]
    when 'contains'
      ["json_extract(data, '$.#{field_slug}') LIKE ?", ["%#{value}%"]]
    when 'not_contains'
      ["json_extract(data, '$.#{field_slug}') NOT LIKE ?", ["%#{value}%"]]
    when 'is_empty'
      ["(json_extract(data, '$.#{field_slug}') IS NULL OR json_extract(data, '$.#{field_slug}') = '')", []]
    when 'is_not_empty'
      ["(json_extract(data, '$.#{field_slug}') IS NOT NULL AND json_extract(data, '$.#{field_slug}') != '')", []]
    end
  end

  def translate_numeric_filter(field_slug, comparison, value)
    case comparison
    when 'is_equal_to'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) = ?", [value.to_f]]
    when 'is_not_equal_to'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) != ?", [value.to_f]]
    when 'is_greater_than'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) > ?", [value.to_f]]
    when 'is_less_than'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) < ?", [value.to_f]]
    when 'is_equal_or_greater_than'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) >= ?", [value.to_f]]
    when 'is_equal_or_less_than'
      ["CAST(json_extract(data, '$.#{field_slug}') AS REAL) <= ?", [value.to_f]]
    end
  end

  def translate_date_filter(field_slug, comparison, value)
    # Parse SmartSuite date format
    timestamp = parse_smartsuite_date(value)

    case comparison
    when 'is', 'is_on'
      # Same day
      start_of_day = timestamp - (timestamp % 86400)
      end_of_day = start_of_day + 86400
      ["CAST(json_extract(data, '$.#{field_slug}') AS INTEGER) BETWEEN ? AND ?", [start_of_day, end_of_day]]
    when 'is_before'
      ["CAST(json_extract(data, '$.#{field_slug}') AS INTEGER) < ?", [timestamp]]
    when 'is_on_or_after'
      ["CAST(json_extract(data, '$.#{field_slug}') AS INTEGER) >= ?", [timestamp]]
    when 'is_on_or_before'
      ["CAST(json_extract(data, '$.#{field_slug}') AS INTEGER) <= ?", [timestamp]]
    end
  end

  def translate_select_filter(field_slug, comparison, value)
    # Hybrid approach: Use indexed column if available
    if @cache.has_indexed_field?(@table_id, field_slug)
      # Use denormalized column (fast)
      case comparison
      when 'is'
        ["status = ?", [value]]
      when 'is_any_of'
        placeholders = value.map { '?' }.join(',')
        ["status IN (#{placeholders})", value]
      end
    else
      # Fallback to JSON
      case comparison
      when 'is'
        ["json_extract(data, '$.#{field_slug}') = ?", [value]]
      when 'is_any_of'
        # Multiple OR conditions
        conditions = value.map { "json_extract(data, '$.#{field_slug}') = ?" }.join(' OR ')
        ["(#{conditions})", value]
      end
    end
  end

  def translate_array_filter(field_slug, comparison, value)
    case comparison
    when 'has_any_of'
      # Check if JSON array contains any of the values
      conditions = value.map do
        "EXISTS (SELECT 1 FROM json_each(json_extract(data, '$.#{field_slug}')) WHERE value = ?)"
      end.join(' OR ')
      ["(#{conditions})", value]
    when 'has_all_of'
      # Check if JSON array contains all values
      conditions = value.map do
        "EXISTS (SELECT 1 FROM json_each(json_extract(data, '$.#{field_slug}')) WHERE value = ?)"
      end.join(' AND ')
      ["(#{conditions})", value]
    when 'is_empty'
      ["(json_extract(data, '$.#{field_slug}') IS NULL OR json_array_length(json_extract(data, '$.#{field_slug}')) = 0)", []]
    end
  end

  def parse_smartsuite_date(value)
    if value.is_a?(Hash)
      # SmartSuite date object
      case value['date_mode']
      when 'exact_date'
        Time.parse(value['date_mode_value']).to_i
      when 'today'
        Time.now.beginning_of_day.to_i
      when 'days_ago'
        (Time.now - value['date_mode_value'].to_i * 86400).to_i
      end
    else
      Time.parse(value).to_i
    end
  end
end
```

### Usage Example:

```ruby
# User provides SmartSuite filter
smartsuite_filter = {
  'operator' => 'and',
  'fields' => [
    {'field' => 'status', 'comparison' => 'is', 'value' => 'Active'},
    {'field' => 'due_date', 'comparison' => 'is_on_or_after', 'value' => {'date_mode' => 'today'}}
  ]
}

# Translate to SQL
translator = FilterTranslator.new(table_id, cache)
where_clause, params = translator.translate_to_sql(smartsuite_filter)

# Execute query
records = @db.execute(
  "SELECT id, title, data FROM records WHERE table_id = ? AND (#{where_clause})",
  table_id, *params
)

# Result: Fast query against cache, no API call needed!
```

---

## Recommendations Summary

### 1. ORM Choice: **Raw SQLite3** ✅
- Zero dependencies
- Maximum performance
- Perfect for MCP server
- Create thin helper layer for common queries

### 2. Fetch Strategy: **Aggressive** ✅
- Always fetch full responses (never filter API fields)
- Proactively fetch related data (tables when fetching solution)
- Warm cache on startup
- Use smart thresholds (don't fetch 100+ tables automatically)

### 3. Record Mapping: **Hybrid Approach** ✅
- Store full record as JSON blob in `data` column
- Denormalize common fields: `title`, `status`, `assigned_to`, `due_date`
- Create indexes on denormalized fields
- Use JSON functions for custom field queries
- Implement FilterTranslator for SmartSuite → SQL conversion

### Implementation Priority:

**Phase 1: Foundation**
- Raw SQLite with helper methods
- Basic cache_entries table
- TTL and invalidation logic

**Phase 2: Metadata Caching**
- Solutions, tables, members (JSON approach)
- Aggressive fetching for metadata
- Cache warming

**Phase 3: Record Caching**
- Hybrid approach (JSON + denormalized common fields)
- FilterTranslator implementation
- Short TTL (5 min)

**Phase 4: Optimization**
- Monitor cache hit rates
- Adjust denormalized fields based on usage
- Fine-tune aggressive fetch thresholds

---

*Design document v1.0 - Deep Dive*
