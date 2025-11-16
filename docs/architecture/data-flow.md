# Data Flow Architecture

Detailed data flow diagrams for all major operations in SmartSuite MCP Server.

## Overview

This document traces the path of data through the system for different operations, showing how requests flow from Claude through the server layers to SmartSuite and back.

**Covered flows:**
- Query operations (cache hit vs miss)
- Mutation operations (create/update/delete)
- Schema operations (table/field management)
- Statistics tracking
- Error propagation

---

## Query Flow: Cache Hit

**Scenario:** User queries records from a cached table

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Show me 10 active tasks with status and priority"            │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC request
                            │ {"method": "tools/call",
                            │  "params": {"name": "list_records", ...}}
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER (smartsuite_server.rb)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. Parse JSON-RPC request                                │  │
│  │ 2. Route to handle_tools_call()                          │  │
│  │ 3. Extract: name="list_records"                          │  │
│  │             arguments={table_id, fields, limit, filter}  │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Call SmartSuiteClient method
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│            API CLIENT (lib/smartsuite_client.rb)                │
│  RecordOperations.list_records(table_id, limit, offset,        │
│                                  fields:, filter:)              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Check cache
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER (lib/smartsuite/cache_layer.rb)        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. Check cache_valid?(table_id)                          │  │
│  │    - Query cache_metadata table                          │  │
│  │    - Check expires_at > DateTime.now                     │  │
│  │    - Result: VALID ✓                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Cache HIT
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│             CACHE QUERY (lib/smartsuite/cache_query.rb)         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ query = CacheQuery.new(db, table_id)                     │  │
│  │   .select(fields)                                        │  │
│  │   .where(field: 'status', operator: 'is', value: 'Active')│  │
│  │   .limit(10)                                             │  │
│  │   .offset(0)                                             │  │
│  │                                                           │  │
│  │ SQL: SELECT id, status, priority                         │  │
│  │      FROM cache_tbl_abc123                               │  │
│  │      WHERE status = 'Active'                             │  │
│  │      LIMIT 10 OFFSET 0                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Execute SQL
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                SQLITE (~/.smartsuite_mcp_cache.db)              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ cache_tbl_abc123:                                        │  │
│  │   id           | status  | priority | _cached_at        │  │
│  │   rec_123      | Active  | High     | 2025-01-15T10:00  │  │
│  │   rec_456      | Active  | Medium   | 2025-01-15T10:00  │  │
│  │   rec_789      | Active  | Low      | 2025-01-15T10:00  │  │
│  │   ... (7 more records)                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│  Returns: 10 records                                            │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Raw records
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│         RESPONSE FORMATTER (lib/smartsuite/formatters/)         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ format_records(records, total_count: 127)                │  │
│  │                                                           │  │
│  │ Output:                                                   │  │
│  │ === RECORDS (10 of 127 total) ===                        │  │
│  │                                                           │  │
│  │ --- Record 1 of 10 ---                                   │  │
│  │ id: rec_123                                              │  │
│  │ status: Active                                           │  │
│  │ priority: High                                           │  │
│  │                                                           │  │
│  │ --- Record 2 of 10 ---                                   │  │
│  │ ...                                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Plain text response
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER (smartsuite_server.rb)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Wrap in MCP response format:                             │  │
│  │ {                                                         │  │
│  │   "jsonrpc": "2.0",                                       │  │
│  │   "id": 3,                                                │  │
│  │   "result": {                                             │  │
│  │     "content": [{                                         │  │
│  │       "type": "text",                                     │  │
│  │       "text": "=== RECORDS (10 of 127 total) ===\n..."   │  │
│  │     }],                                                   │  │
│  │     "isError": false                                      │  │
│  │   }                                                        │  │
│  │ }                                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ stdout
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  Displays: "Here are 10 active tasks:                          │
│            1. rec_123 - High priority                           │
│            2. rec_456 - Medium priority..."                     │
└─────────────────────────────────────────────────────────────────┘

Time: 5-20ms
API calls: 0
```

---

## Query Flow: Cache Miss

**Scenario:** User queries records from uncached or expired table

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Show me 10 customers from the CRM table"                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER → CACHE LAYER                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. Check cache_valid?(table_id)                          │  │
│  │    - Query cache_metadata                                │  │
│  │    - Result: INVALID (expired or not cached) ✗          │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Cache MISS → Trigger refresh
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER: refresh_cache(table_id)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP 1: Get table structure                              │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ GET /applications/{table_id}
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│         HTTP CLIENT (lib/smartsuite/api/http_client.rb)         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ api_request('GET', "/applications/tbl_abc123")           │  │
│  │   Headers:                                                │  │
│  │     Authorization: Token #{SMARTSUITE_API_KEY}           │  │
│  │     Account-Id: #{SMARTSUITE_ACCOUNT_ID}                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SMARTSUITE API                                │
│  Returns table structure with field definitions:                │
│  {                                                               │
│    "id": "tbl_abc123",                                          │
│    "name": "Customers",                                         │
│    "structure": [                                               │
│      {"slug": "customer_name", "field_type": "textfield"},     │
│      {"slug": "email", "field_type": "emailfield"},            │
│      {"slug": "status", "field_type": "singleselectfield"},    │
│      ...                                                        │
│    ]                                                            │
│  }                                                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Structure response
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER: refresh_cache() continued             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP 2: Create SQLite table with proper schema           │  │
│  │                                                           │  │
│  │ CREATE TABLE IF NOT EXISTS cache_tbl_abc123 (            │  │
│  │   id TEXT PRIMARY KEY,                                   │  │
│  │   customer_name TEXT,                                    │  │
│  │   email TEXT,                                            │  │
│  │   status TEXT,                                           │  │
│  │   _cached_at TEXT NOT NULL                               │  │
│  │ )                                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP 3: Fetch ALL records (paginated)                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Loop: offset=0, limit=1000
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP CLIENT (batch fetch)                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Iteration 1: offset=0, limit=1000                        │  │
│  │   POST /applications/tbl_abc123/records/list/            │  │
│  │        ?limit=1000&offset=0                              │  │
│  │   Returns: 1000 records                                  │  │
│  │                                                           │  │
│  │ Iteration 2: offset=1000, limit=1000                     │  │
│  │   POST /applications/tbl_abc123/records/list/            │  │
│  │        ?limit=1000&offset=1000                           │  │
│  │   Returns: 834 records                                   │  │
│  │                                                           │  │
│  │ Iteration 3: offset=1834, limit=1000                     │  │
│  │   Returns: 0 records → STOP                              │  │
│  │                                                           │  │
│  │ Total fetched: 1,834 records                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ All records → ApiStatsTracker logs 2 calls
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│       API STATS TRACKER (lib/api_stats_tracker.rb)              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ FOR EACH API CALL:                                       │  │
│  │   INSERT INTO api_calls (                                │  │
│  │     session_id,                                          │  │
│  │     user_hash,     -- SHA256(API_KEY)[0..8]             │  │
│  │     solution_id,                                         │  │
│  │     table_id,                                            │  │
│  │     http_method,   -- 'POST'                            │  │
│  │     endpoint,      -- '/records/list/'                  │  │
│  │     timestamp                                            │  │
│  │   ) VALUES (...)                                         │  │
│  │                                                           │  │
│  │ Total logged: 2 API calls                                │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Continue with cache storage
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER: refresh_cache() continued             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP 4: Store in SQLite (transaction)                    │  │
│  │                                                           │  │
│  │ BEGIN TRANSACTION;                                        │  │
│  │   DELETE FROM cache_tbl_abc123;  -- Clear old data      │  │
│  │                                                           │  │
│  │   INSERT INTO cache_tbl_abc123                           │  │
│  │   VALUES ('rec_1', 'Acme Corp', 'info@acme.com', ...);  │  │
│  │   ... (1,833 more inserts)                               │  │
│  │ COMMIT;                                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP 5: Update cache metadata                            │  │
│  │                                                           │  │
│  │ INSERT OR REPLACE INTO cache_metadata VALUES (           │  │
│  │   table_id: 'tbl_abc123',                                │  │
│  │   cached_at: '2025-01-15T10:00:00Z',                     │  │
│  │   expires_at: '2025-01-15T14:00:00Z',  -- +4 hours      │  │
│  │   ttl_seconds: 14400,                                    │  │
│  │   record_count: 1834,                                    │  │
│  │   schema_hash: 'abc123...'                               │  │
│  │ )                                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Cache now valid
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│         CACHE QUERY → SQLITE → FORMATTER → SERVER               │
│  [Same as Cache Hit flow from this point]                      │
│                                                                 │
│  1. Query cached data with SQL                                 │
│  2. Get 10 records                                             │
│  3. Format as plain text                                       │
│  4. Return to Claude                                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  Displays results                                               │
└─────────────────────────────────────────────────────────────────┘

Time: 500-2000ms (first query), then 5-20ms (subsequent)
API calls: 2-5 (pagination), then 0
```

---

## Mutation Flow: Create Record

**Scenario:** User creates a new record

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Create a task: Title='Budget Review', Status='Active',       │
│   Priority='High'"                                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER                                       │
│  handle_tools_call("create_record", {                           │
│    table_id: "tbl_abc123",                                      │
│    data: {                                                      │
│      title: "Budget Review",                                   │
│      status: "Active",                                         │
│      priority: "High"                                          │
│    }                                                            │
│  })                                                             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│           RECORD OPERATIONS (lib/smartsuite/api/)               │
│  create_record(table_id, data)                                 │
│    - No cache interaction                                      │
│    - Direct API call                                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │ POST request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP CLIENT                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ api_request('POST',                                      │  │
│  │   "/applications/tbl_abc123/records/",                   │  │
│  │   {title: "Budget Review", status: "Active", ...}        │  │
│  │ )                                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SMARTSUITE API                                │
│  Creates record                                                 │
│  Returns:                                                       │
│  {                                                              │
│    "id": "rec_new_123",                                        │
│    "title": "Budget Review",                                   │
│    "status": "Active",                                         │
│    "priority": "High",                                         │
│    "created_on": "2025-01-15T10:30:00Z"                        │
│  }                                                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Response
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              API STATS TRACKER                                   │
│  Logs API call:                                                 │
│    endpoint: '/records/'                                        │
│    http_method: 'POST'                                          │
│    table_id: 'tbl_abc123'                                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER: NO ACTION                              │
│  ⚠️ Cache NOT invalidated (by design)                           │
│  - Cache will expire naturally by TTL                           │
│  - User can bypass_cache on next query for fresh data          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│         RESPONSE FORMATTER                                       │
│  format_record({                                                │
│    id: "rec_new_123",                                          │
│    title: "Budget Review",                                     │
│    ...                                                          │
│  })                                                             │
│                                                                 │
│  Output:                                                        │
│  === CREATED RECORD ===                                        │
│  id: rec_new_123                                               │
│  title: Budget Review                                          │
│  status: Active                                                │
│  priority: High                                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "I've created the task. The new task ID is rec_new_123."      │
└─────────────────────────────────────────────────────────────────┘

Time: 200-500ms
API calls: 1
Cache: NOT updated (expires by TTL)
```

---

## Schema Operation Flow: Add Field

**Scenario:** User adds a new field to a table

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Add a 'Department' dropdown field to Employees table with    │
│   options: Engineering, Sales, Marketing"                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER                                       │
│  handle_tools_call("add_field", {                               │
│    table_id: "tbl_emp_123",                                     │
│    field_data: {                                                │
│      slug: "department",                                       │
│      label: "Department",                                      │
│      field_type: "singleselectfield",                          │
│      params: {                                                 │
│        choices: [{label: "Engineering"}, {label: "Sales"}, ...]│
│      }                                                          │
│    }                                                            │
│  })                                                             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│           FIELD OPERATIONS (lib/smartsuite/api/)                │
│  add_field(table_id, field_data, field_position: {},           │
│            auto_fill_structure_layout: true)                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │ POST request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP CLIENT                                   │
│  api_request('POST',                                            │
│    "/applications/tbl_emp_123/add_field/",                      │
│    {field: {...}, field_position: {}, auto_fill: true}          │
│  )                                                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SMARTSUITE API                                │
│  Adds field to table schema                                     │
│  Returns: {} (empty response on success)                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Success
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER: Schema Change Detection                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ On next list_records query:                              │  │
│  │   1. Check cache_valid?(table_id)                        │  │
│  │   2. Get cached schema_hash                              │  │
│  │   3. Fetch current schema from API                       │  │
│  │   4. Compare hashes                                       │  │
│  │   5. Mismatch → Mark cache invalid                       │  │
│  │   6. Trigger refresh_cache()                             │  │
│  │   7. Create new SQLite table with updated schema         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Result: Cache automatically adapts to schema changes          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "I've added the Department field. The next time you query     │
│   employees, it will include the department column."            │
└─────────────────────────────────────────────────────────────────┘

Time: 200-400ms
API calls: 1 (add field) + 1 (schema fetch on next query)
Cache: Invalidated on next query (automatic schema evolution)
```

---

## Statistics Flow

**Scenario:** Continuous API tracking throughout session

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVER STARTUP                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 1. Initialize ApiStatsTracker                            │  │
│  │ 2. Generate session_id: 20250115_100000_abc123          │  │
│  │ 3. Hash API key: SHA256(key)[0..8] = "a1b2c3d4"         │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                ┌───────────┼───────────┐
                │           │           │
                ▼           ▼           ▼
         [Query 1]    [Query 2]   [Query 3]
                │           │           │
                └───────────┼───────────┘
                            │ Each API call
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│           API STATS TRACKER (every HTTP request)                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ FOR EACH api_request() call:                             │  │
│  │                                                           │  │
│  │   track_api_call(                                        │  │
│  │     solution_id: 'sol_abc',   -- from request            │  │
│  │     table_id: 'tbl_123',      -- from request            │  │
│  │     http_method: 'GET',       -- from request            │  │
│  │     endpoint: '/applications/'-- from request            │  │
│  │   )                                                       │  │
│  │                                                           │  │
│  │   INSERT INTO api_calls (                                │  │
│  │     id,                       -- autoincrement           │  │
│  │     session_id,               -- '20250115_100000_...'  │  │
│  │     user_hash,                -- 'a1b2c3d4'             │  │
│  │     solution_id,              -- 'sol_abc'              │  │
│  │     table_id,                 -- 'tbl_123'              │  │
│  │     http_method,              -- 'GET'                   │  │
│  │     endpoint,                 -- '/applications/'        │  │
│  │     timestamp                 -- '2025-01-15T10:00:00Z' │  │
│  │   )                                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Continues throughout session
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                SQLITE: api_calls table                           │
│  Growing log of all API calls:                                  │
│                                                                 │
│  id | session_id          | user_hash | endpoint      | ...    │
│  1  | 20250115_100000_... | a1b2c3d4  | /solutions/   | ...    │
│  2  | 20250115_100000_... | a1b2c3d4  | /applications/| ...    │
│  3  | 20250115_100000_... | a1b2c3d4  | /records/list/| ...    │
│  4  | 20250115_100000_... | a1b2c3d4  | /records/list/| ...    │
│  ...                                                            │
└───────────────────────────┬─────────────────────────────────────┘
                            │ User requests stats
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│           get_api_stats() TOOL                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Query aggregations:                                       │  │
│  │                                                           │  │
│  │ SELECT COUNT(*) FROM api_calls                           │  │
│  │   WHERE session_id = ?;                                  │  │
│  │ Result: 127 total calls                                  │  │
│  │                                                           │  │
│  │ SELECT endpoint, COUNT(*) as count                       │  │
│  │   FROM api_calls                                         │  │
│  │   GROUP BY endpoint                                      │  │
│  │   ORDER BY count DESC;                                   │  │
│  │ Result: /records/list/: 45, /applications/: 12, ...     │  │
│  │                                                           │  │
│  │ SELECT table_id, COUNT(*) as count                       │  │
│  │   FROM api_calls                                         │  │
│  │   WHERE table_id IS NOT NULL                             │  │
│  │   GROUP BY table_id                                      │  │
│  │   ORDER BY count DESC;                                   │  │
│  │ Result: tbl_123: 28, tbl_456: 15, ...                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Formatted statistics
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Here are your API statistics:                                │
│                                                                 │
│   Total Calls: 127                                             │
│   Session: 20250115_100000_abc123                             │
│                                                                 │
│   By Endpoint:                                                 │
│     /records/list/: 45 calls                                   │
│     /applications/: 12 calls                                   │
│     /solutions/: 8 calls                                       │
│                                                                 │
│   Top Tables:                                                  │
│     tbl_123: 28 calls                                          │
│     tbl_456: 15 calls"                                         │
└─────────────────────────────────────────────────────────────────┘

Tracking: Continuous (every API call)
Storage: SQLite (same database as cache)
Privacy: API key hashed with SHA256
Impact: Silent (never interrupts user work)
```

---

## Error Propagation Flow

**Scenario:** API error handling through layers

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "Show me records from invalid table ID"                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER                                       │
│  handle_tools_call("list_records", {                            │
│    table_id: "invalid_xyz",                                     │
│    fields: ["status"],                                          │
│    limit: 10                                                    │
│  })                                                             │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Try execution
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Check cache_valid?("invalid_xyz")                        │  │
│  │   - Query: SELECT * FROM cache_metadata                  │  │
│  │             WHERE table_id = 'invalid_xyz'               │  │
│  │   - Result: Empty (not cached)                           │  │
│  │   - Decision: Fetch from API                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ GET table structure
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP CLIENT                                   │
│  api_request('GET', "/applications/invalid_xyz")                │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SMARTSUITE API                                │
│  HTTP 404 Not Found                                             │
│  {                                                              │
│    "error": {                                                   │
│      "message": "Application not found",                        │
│      "code": "NOT_FOUND"                                        │
│    }                                                            │
│  }                                                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Error response
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP CLIENT                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Detect status code: 404                                  │  │
│  │ Raise exception:                                         │  │
│  │   RuntimeError: "SmartSuite API Error (404):             │  │
│  │                  Application not found"                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Exception bubbles up
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              CACHE LAYER                                         │
│  Exception propagates (no catch)                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              RECORD OPERATIONS                                   │
│  Exception propagates (no catch)                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│               SERVER LAYER                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ rescue => e                                               │  │
│  │   {                                                       │  │
│  │     content: [{                                           │  │
│  │       type: "text",                                       │  │
│  │       text: "Error: SmartSuite API Error (404):          │  │
│  │                Application not found"                    │  │
│  │     }],                                                   │  │
│  │     isError: true                                         │  │
│  │   }                                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ MCP error result
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         CLAUDE                                   │
│  "I encountered an error: The table ID 'invalid_xyz' was not   │
│   found. Could you provide the correct table ID?"               │
└─────────────────────────────────────────────────────────────────┘

Error Handling Strategy:
- HTTP errors caught by HttpClient, raised as exceptions
- Exceptions propagate through layers
- Server layer catches all and returns MCP error result
- Claude receives error, explains to user
```

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
