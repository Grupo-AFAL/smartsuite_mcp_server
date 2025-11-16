# Architecture Overview

High-level architecture of the SmartSuite MCP Server.

## System Architecture

The SmartSuite MCP Server is a Ruby-based MCP (Model Context Protocol) server that bridges Claude with SmartSuite's REST API. It implements an intelligent caching layer, token optimization strategies, and comprehensive API tracking.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Claude                              │
│                    (MCP Client)                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ JSON-RPC over stdin/stdout
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                  SmartSuite MCP Server                       │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │            Server Layer (smartsuite_server.rb)         │  │
│  │  - JSON-RPC protocol handling                          │  │
│  │  - MCP method routing (initialize, tools, prompts)     │  │
│  │  - Error handling and notifications                    │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────┴───────────────────────────────┐  │
│  │              MCP Protocol Layer (lib/smartsuite/mcp/)  │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ ToolRegistry │  │PromptRegistry│  │ Resource     │  │  │
│  │  │  (26 tools)  │  │  (8 prompts) │  │  Registry    │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────┴───────────────────────────────┐  │
│  │       API Client Layer (lib/smartsuite/api/)           │  │
│  │  ┌─────────────────┐ ┌─────────────────┐               │  │
│  │  │   HttpClient    │ │ ApiStatsTracker │               │  │
│  │  │ (authentication)│ │  (monitoring)   │               │  │
│  │  └────────┬────────┘ └─────────────────┘               │  │
│  │           │                                            │  │
│  │  ┌────────┴──────────────────────────────────────────┐ │  │
│  │  │        SmartSuiteClient (includes modules)        │ │  │
│  │  │                                                   │ │  │
│  │  │  WorkspaceOps │ TableOps │ RecordOps              │ │  │
│  │  │  FieldOps     │ MemberOps│ CommentOps             │ │  │
│  │  │  ViewOps                                          │ │  │
│  │  └───────────────────────────────────────────────────┘ │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────┴───────────────────────────────┐  │
│  │         Cache Layer (lib/smartsuite/)                  │  │
│  │  ┌──────────────┐    ┌────────────────────────┐        │  │
│  │  │  CacheLayer  │───▶│  CacheQuery            │        │  │
│  │  │ (TTL, CRUD)  │    │ (chainable SQL builder)│        │  │
│  │  └──────┬───────┘    └────────────────────────┘        │  │
│  │         │                                              │  │
│  │         ▼                                              │  │
│  │  ┌────────────────────────────────────────────┐        │  │
│  │  │   SQLite (~/.smartsuite_mcp_cache.db)      │        │  │
│  │  │  - Dynamic tables (one per SmartSuite tbl) │        │  │
│  │  │  - API call logs                           │        │  │
│  │  │  - Statistics                              │        │  │
│  │  └────────────────────────────────────────────┘        │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────┴───────────────────────────────┐  │
│  │      Formatters Layer (lib/smartsuite/formatters/)     │  │
│  │  - ResponseFormatter (plain text, filtering)           │  │
│  │  - Token optimization (no truncation)                  │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────────────┘
                           │ HTTPS REST API
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                      SmartSuite API                          │
│                  (app.smartsuite.com/api/v1/)                │
└──────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Server Layer

**File:** `smartsuite_server.rb` (262 lines)

**Responsibilities:**

- MCP protocol handler and main entry point
- JSON-RPC communication over stdin/stdout
- Routes MCP protocol methods to appropriate registries
- Error handling and notifications
- Does NOT handle SmartSuite API calls directly

**Key methods:**

- `handle_request(request)` - Process incoming JSON-RPC
- `handle_tool_call(name, arguments)` - Execute SmartSuite operations
- `send_response(response)` - Send JSON-RPC to Claude

### 2. MCP Protocol Layer

**Location:** `lib/smartsuite/mcp/`

**Components:**

**ToolRegistry** (`tool_registry.rb`, 633 lines)

- Defines all 26 tool schemas
- Organized by category (workspace, tables, records, etc.)
- Tool parameter validation
- Returns tool definitions for `tools/list`

**PromptRegistry** (`prompt_registry.rb`, 447 lines)

- 8 example prompts for common filter patterns
- Demonstrates correct filter syntax
- Returns prompt templates for `prompts/list`

**ResourceRegistry** (`resource_registry.rb`, 15 lines)

- Resource listing (currently empty)
- Extensibility for future resource types

### 3. API Client Layer

**Location:** `lib/smartsuite/api/`

**HttpClient** (`http_client.rb`, 68 lines)

- HTTP request execution
- Authentication (API key + Account ID headers)
- Request/response logging
- Error handling (401, 429, etc.)

**SmartSuiteClient** (`lib/smartsuite_client.rb`, 30 lines)

- Thin wrapper including all operation modules
- 96% size reduction from original (708 → 30 lines)

**Operation Modules:**

- **WorkspaceOperations** (344 lines) - Solutions, usage analysis, ownership
- **TableOperations** - Table management
- **RecordOperations** (114 lines) - Data CRUD
- **FieldOperations** (103 lines) - Schema management
- **MemberOperations** (281 lines) - Users and teams
- **CommentOperations** (79 lines) - Comments
- **ViewOperations** (88 lines) - Views/reports

### 4. Cache Layer

**Location:** `lib/smartsuite/`

**CacheLayer** (`cache_layer.rb`)

- Dynamic SQLite table creation (one per SmartSuite table)
- TTL management (default: 4 hours)
- Schema evolution (automatic re-caching on structure changes)
- Cache-first query strategy

**CacheQuery** (`cache_query.rb`)

- Chainable query builder for flexible filtering
- SQL generation from SmartSuite filter syntax
- Multi-criteria queries
- Pagination support

**Storage:**

- Single SQLite database: `~/.smartsuite_mcp_cache.db`
- Includes both cache and API statistics
- Persistent across server restarts

### 5. Statistics Tracker

**ApiStatsTracker** (`lib/api_stats_tracker.rb`)

- API usage monitoring with session tracking
- Tracks calls by user, session, solution, table, method, endpoint
- Persists to SQLite (shares database with cache)
- Privacy-preserving (hashes API keys with SHA256)
- Silent operation (never interrupts user work)

### 6. Response Formatters

**ResponseFormatter** (`lib/smartsuite/formatters/response_formatter.rb`)

- Plain text formatting (30-50% token savings vs JSON)
- Table structure filtering (removes 83.8% of UI metadata)
- No value truncation (user controls via field selection)
- "X of Y total" counts for pagination decisions

---

## Data Flow

### Query Flow (Cache Hit)

```
1. Claude sends tool call →
2. Server routes to handler →
3. CacheLayer.get_records(table_id) →
4. Check cache validity (TTL) →
5. Cache valid ✓ →
6. CacheQuery builds SQL →
7. Execute on SQLite →
8. Filter/paginate results →
9. ResponseFormatter converts to plain text →
10. Return to Claude

Time: 5-20ms
API calls: 0
```

### Query Flow (Cache Miss)

```
1. Claude sends tool call →
2. Server routes to handler →
3. CacheLayer.get_records(table_id) →
4. Check cache validity (TTL) →
5. Cache invalid/expired ✗ →
6. HttpClient.api_request() →
7. SmartSuite API (paginated, limit=1000) →
8. ApiStatsTracker logs call →
9. CacheLayer creates/updates SQLite table →
10. Store all records with TTL →
11. CacheQuery builds SQL →
12. Execute on cached data →
13. Filter/paginate results →
14. ResponseFormatter converts to plain text →
15. Return to Claude

Time: 500-2000ms (first time), then 5-20ms
API calls: 1-5 (pagination), then 0
```

### Mutation Flow (Create/Update/Delete)

```
1. Claude sends tool call →
2. Server routes to handler →
3. HttpClient.api_request() (POST/PUT/DELETE) →
4. SmartSuite API →
5. ApiStatsTracker logs call →
6. Cache NOT invalidated →
7. ResponseFormatter converts response →
8. Return to Claude

Notes:
- Cache expires naturally by TTL
- User can bypass cache on next query for fresh data
```

---

## Key Design Patterns

### 1. Cache-First Strategy

**Goal:** Minimize API calls, maximize performance

**Implementation:**

- Every `list_records` query checks cache first
- Cache valid (< 4 hours) → Query SQLite (instant)
- Cache invalid → Fetch ALL records → Cache → Query (one-time cost)
- Mutations never invalidate cache (expires by TTL)

**Benefits:**

- 75%+ API call reduction
- 99% faster responses (5ms vs 1000ms)
- Enables local SQL filtering

### 2. Dynamic Table Creation

**Goal:** Optimize storage and querying per table

**Implementation:**

- Each SmartSuite table → One SQLite table
- Table schema generated from SmartSuite field structure
- Proper column types (TEXT, INTEGER, REAL, DATETIME)
- Records stored with TTL timestamp

**Benefits:**

- Efficient storage
- Fast SQL queries
- Schema evolution support
- Isolated cache per table

### 3. Token Optimization

**Goal:** Minimize Claude's token usage

**Implementation:**

- Plain text responses (not JSON)
- Filtered table structures (only essential fields)
- No value truncation (user controls field selection)
- "X of Y total" counts (helps AI make decisions)

**Benefits:**

- 30-50% token savings on responses
- 83.8% reduction in table structure data
- Better context utilization

### 4. Session Tracking

**Goal:** Monitor usage patterns across server instances

**Implementation:**

- Unique session ID per server instance
- Format: `YYYYMMDD_HHMMSS_random`
- All API calls logged with session ID
- API keys hashed for privacy (SHA256, 8 chars)

**Benefits:**

- Track usage across restarts
- Compare session performance
- Historical analysis
- Privacy-preserving

### 5. Modular Operation Layer

**Goal:** Maintainable, organized codebase

**Implementation:**

- Each SmartSuite resource → One operation module
- Modules included in SmartSuiteClient
- Clear separation of concerns
- Easy to extend

**Benefits:**

- 96% size reduction in main client
- Easy to maintain
- Clear boundaries
- Testable

---

## Technology Stack

### Core

**Language:** Ruby 3.0+

- Standard library only (no external gems)
- Cross-platform (macOS, Linux, Windows)

**Database:** SQLite 3

- Embedded (no server required)
- Single file storage
- ACID compliance
- Fast queries

**Protocol:** MCP (Model Context Protocol)

- JSON-RPC 2.0 over stdin/stdout
- Tool/prompt/resource paradigm

**API:** SmartSuite REST API

- HTTPS
- Token authentication
- Rate limits: 5 req/sec

### Dependencies

**Ruby Standard Library:**

- `json` - JSON parsing
- `net/http` - HTTP client
- `uri` - URL handling
- `time` - Timestamp handling
- `fileutils` - File operations
- `digest` - SHA256 hashing
- `sqlite3` - Database (via stdlib)

**Test:**

- `minitest` - Testing framework
- `rake` - Task runner

---

## Performance Characteristics

### Cache Performance

**Cache HIT:**

- Latency: 5-20ms
- API calls: 0
- Tokens: Minimal (plain text)

**Cache MISS:**

- Latency: 500-2000ms
- API calls: 1-5 (pagination)
- Tokens: Standard

**Target:** 80%+ cache hit rate

### API Rate Limits

**SmartSuite Limits:**

- 5 requests/second
- ~300 requests/minute
- ~18,000 requests/hour

**Server Strategy:**

- Cache-first (reduces calls by 75%+)
- No automatic batching (relies on cache)
- User-controlled bypass

### Token Usage

**Typical record (3 fields, plain text):**

- ~30-50 tokens

**Same record (JSON):**

- ~80-100 tokens

**Savings:** 40-50% per record

**Table structure (filtered):**

- ~100-200 tokens per table

**Same structure (unfiltered):**

- ~600-1200 tokens per table

**Savings:** 83.8%

---

## Scalability

### Horizontal Scaling

**Not designed for:** Multi-user server deployment
**Designed for:** Single-user Claude Desktop integration

Each user runs their own server instance:

- Own cache database
- Own API credentials
- Own session tracking

### Vertical Scaling

**Cache size:** Grows with data

- Typical: 1-50 MB
- Large workspaces: 100-500 MB
- No automatic cleanup (manual via reset)

**Record limits:** No hard limits

- SmartSuite API paginates at 1000/request
- Server fetches all pages for caching
- Large tables (100K+ records) may take longer on first query

### Performance Tuning

**User-controlled:**

- Field selection (fewer fields = less tokens)
- Limit parameter (fewer records = faster)
- Cache bypass (when fresh data needed)

**Server-controlled:**

- Cache TTL (4 hours default)
- Pagination size (1000 per request)
- Plain text formatting (automatic)

---

## Security

### API Credentials

**Storage:** Environment variables

- `SMARTSUITE_API_KEY`
- `SMARTSUITE_ACCOUNT_ID`

**Never stored:** In code, logs, or cache
**Hashed in stats:** SHA256 for privacy

### Data Privacy

**Local storage:** All cache data stays on user's machine
**No telemetry:** No data sent to third parties
**SQLite permissions:** Standard file permissions

### Rate Limiting

**Client-side:** No enforcement (relies on cache)
**Server-side:** SmartSuite enforces 5 req/sec
**On exceed:** 429 errors, throttled to 2 req/sec

---

## Extensibility

### Adding New Tools

1. Add tool schema to `ToolRegistry`
2. Implement handler in server layer
3. Add operation to appropriate module
4. Update tests

### Adding New Operations

1. Create module in `lib/smartsuite/api/`
2. Include in `SmartSuiteClient`
3. Call via `HttpClient`
4. Add error handling

### Extending Cache

1. Add table type to `CacheLayer`
2. Implement schema generation
3. Add TTL config
4. Update query builder if needed

---

## Related Documentation

- **[Caching System](caching-system.md)** - Deep dive into cache design
- **[MCP Protocol](mcp-protocol.md)** - MCP implementation details
- **[Data Flow](data-flow.md)** - Detailed data flow diagrams
- **[Design Decisions](design-decisions.md)** - Architectural choices

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
