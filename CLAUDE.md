# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Model Context Protocol (MCP) server for SmartSuite, written in Ruby. It enables AI assistants to interact with SmartSuite workspaces through the MCP protocol via stdin/stdout communication.

## 📚 Full Documentation

For comprehensive documentation, see the `docs/` directory:

- **[Documentation Index](docs/README.md)** - Complete documentation map
- **[Getting Started](docs/getting-started/)** - Installation, quick start, troubleshooting
- **[Guides](docs/guides/)** - User guide, caching, filtering, performance
- **[API Reference](docs/api/)** - Complete API documentation by module
- **[Architecture](docs/architecture/)** - System design and implementation details
- **[Examples](examples/)** - Practical usage patterns

This CLAUDE.md file contains essential information for Claude Code. For detailed documentation, always refer to the `docs/` directory.

## Essential Commands

### Testing
```bash
# Run all tests
bundle exec rake test

# Run with verbose output
bundle exec rake test TESTOPTS="-v"

# Run tests directly
ruby test/test_smartsuite_server.rb
```

### Development Setup
```bash
# Install dependencies
bundle install

# Make server executable
chmod +x smartsuite_server.rb

# Set environment variables (required)
export SMARTSUITE_API_KEY=your_api_key
export SMARTSUITE_ACCOUNT_ID=your_account_id

# Run server manually for testing
ruby smartsuite_server.rb
```

### Manual Testing
The server communicates via stdin/stdout using JSON-RPC protocol. Test by sending JSON messages:
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby smartsuite_server.rb
```

## Utility Scripts

The project includes utility scripts in `bin/` for administrative and batch operations. These are **separate from the MCP server** and run directly via CLI.

### Batch Markdown Converter (`bin/convert_markdown_sessions`)

**Purpose:** Bulk convert multiple SmartSuite records from Markdown to SmartDoc format

**Use Case:** Automated webhook data (e.g., Read.ai meeting transcripts) that arrives as Markdown but needs to be formatted as rich text in SmartSuite.

**Key Features:**
- Single API call to fetch filtered records (not n+1)
- Local conversion (0 AI tokens)
- Bulk updates in configurable batches
- Dry-run mode for safety
- Smart skipping (already converted, empty content, etc.)
- External configuration via `.conversion_config` (gitignored for privacy)

**Usage:**
```bash
# Basic usage (uses .conversion_config)
bin/convert_markdown_sessions

# Dry-run to preview changes
bin/convert_markdown_sessions --dry-run

# Test with limited records
bin/convert_markdown_sessions --limit 10

# Override config values
bin/convert_markdown_sessions --from-status pending --to-status complete
```

**Configuration:**
Create `.conversion_config` from `.conversion_config.example`:
```bash
cp .conversion_config.example .conversion_config
# Edit with your table IDs, field slugs, and status values
```

**Documentation:** See `docs/guides/markdown-batch-conversion.md`

### When to Use Utility Scripts vs MCP Tools

| Scenario | Use |
|----------|-----|
| Bulk operation (50+ records) | Utility script |
| Automated/scheduled task | Utility script |
| Data migration/transformation | Utility script |
| Single record operation | MCP tool (via AI) |
| Exploratory analysis | MCP tool (via AI) |
| AI-guided workflow | MCP tool (via AI) |

## Development Workflow

### Starting a New Feature

**ALWAYS create a feature branch** before starting work on a new feature:

```bash
# Create and checkout a new feature branch
git checkout -b feature/feature-name

# Examples:
git checkout -b feature/add-bulk-delete
git checkout -b feature/improve-error-handling
git checkout -b fix/cache-invalidation-bug
```

Branch naming conventions:
- `feature/` - New features or enhancements
- `fix/` - Bug fixes
- `refactor/` - Code refactoring without functional changes
- `docs/` - Documentation updates

### Completing a Feature

**BEFORE merging or creating a PR**, complete this checklist:

1. **Documentation** ✅
   - **ALWAYS update CHANGELOG.md** with changes under `[Unreleased]` section (required for ALL changes, enforced by GitHub Actions)
   - Update ROADMAP.md if the feature affects planned milestones
   - Update relevant docs in `docs/` directory
   - Add/update YARD documentation for new/modified methods
   - Update CLAUDE.md if workflow or architecture changes

2. **Tests** ✅
   - Run full test suite: `bundle exec rake test`
   - Ensure tests pass with 0 failures
   - Add tests for new functionality
   - Maintain or improve code coverage (current baseline: 93%, target: 90% - exceeded!)
   - Consider edge cases and error scenarios

3. **Code Quality** ✅
   - Run RuboCop: `bundle exec rubocop`
   - Fix any style violations: `bundle exec rubocop -A` (auto-correct)
   - Run Reek for code smells: `bundle exec reek`
   - Ensure YARD coverage: `bundle exec yard stats --list-undoc`

4. **Linting** ✅
   - Markdown files: Check with markdownlint
   - Ensure CHANGELOG follows Keep a Changelog format
   - Check for proper heading structure and formatting

5. **Refactoring Opportunities** ✅
   - Look for code duplication (DRY principle)
   - Check if new helpers/modules could be extracted
   - Verify proper use of existing modules (API::Base, FilterBuilder, etc.)
   - Consider token optimization opportunities
   - Review error handling consistency

6. **GitHub Actions** ✅
   - Verify all workflows pass locally before pushing
   - Check test coverage meets baseline
   - Ensure security audit passes (bundle audit)

**Example completion workflow:**
```bash
# 1. Run all checks
bundle exec rake test
bundle exec rubocop -A
bundle exec reek
bundle exec yard stats --list-undoc

# 2. Update documentation (REQUIRED: CHANGELOG.md must ALWAYS be updated)
# Edit CHANGELOG.md (add to [Unreleased] section), ROADMAP.md, relevant docs

# 3. Commit changes
git add .
git commit -m "feat: Add feature description

Detailed description of changes...

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# 4. Push and verify GitHub Actions
git push origin feature/feature-name

# 5. If ready for release, merge to main and create release tag
```

## Architecture

The codebase follows a modular architecture with clear separation of concerns across three layers:

### 1. Server Layer
**SmartSuiteServer** (`smartsuite_server.rb`, 262 lines)
- **Responsibility**: MCP protocol handler and main entry point
- Manages JSON-RPC communication over stdin/stdout
- Routes MCP protocol methods to appropriate registries
- Handles errors and notifications
- Does NOT handle SmartSuite API calls or tool schemas directly

### 2. MCP Protocol Layer (`lib/smartsuite/mcp/`)
Handles MCP protocol responses and schemas:

- **ToolRegistry** (`tool_registry.rb`): All 35 tool schemas organized by category
- **PromptRegistry** (`prompt_registry.rb`, 447 lines): 8 prompt templates covering all major filter patterns
- **ResourceRegistry** (`resource_registry.rb`, 15 lines): Resource listing (currently empty)

### 3. API Client Layer (`lib/smartsuite/api/`)
Handles SmartSuite API communication:

- **HttpClient** (`http_client.rb`, 68 lines): HTTP request execution, authentication, logging
- **WorkspaceOperations** (`workspace_operations.rb`, 344 lines): Solution management, usage analysis, owner filtering, and recent update tracking
- **TableOperations** (`table_operations.rb`): Table/application management (list, get, create)
- **RecordOperations** (`record_operations.rb`, 528 lines): Record CRUD operations, bulk operations, file attachment and URLs, deleted records management
- **FieldOperations** (`field_operations.rb`, 103 lines): Table schema management (add/update/delete fields)
- **MemberOperations** (`member_operations.rb`, 281 lines): User and team management, member search
- **CommentOperations** (`comment_operations.rb`, 79 lines): Comment management (list, add comments)
- **ViewOperations** (`view_operations.rb`, 88 lines): View/report management (get records, create views)

**SmartSuiteClient** (`lib/smartsuite_client.rb`, 30 lines)
- Thin wrapper that includes all API modules
- 30 lines vs original 708 lines (96% reduction)

### 4. Formatters Layer (`lib/smartsuite/formatters/`)
Implements token optimization and format conversion:

- **ResponseFormatter** (`response_formatter.rb`): Response filtering, supports multiple output formats (no value truncation per user request)
- **ToonFormatter** (`toon_formatter.rb`): TOON (Token-Oriented Object Notation) encoding for maximum token savings (~50-60% vs JSON)
- **MarkdownToSmartdoc** (`markdown_to_smartdoc.rb`): Converts Markdown text to SmartSuite's SmartDoc format (rich text fields)

### 5. Cache Layer (`lib/smartsuite/cache/`)
SQLite-based persistent caching for SmartSuite data (v1.7+: modular architecture):

- **Cache::Layer** (`cache/layer.rb`): Core caching interface, dynamic table creation
- **Cache::Metadata** (`cache/metadata.rb`): Table registry, schema management, TTL config
- **Cache::Performance** (`cache/performance.rb`): Hit/miss tracking, statistics
- **Cache::Migrations** (`cache/migrations.rb`): Schema migrations, data migration helpers
- **Cache::Query** (`cache/query.rb`): Chainable query builder for flexible multi-criteria queries
- **Database**: `~/.smartsuite_mcp_cache.db` (single file, includes both cache and API stats)

### 6. Supporting Components
**ApiStatsTracker** (`lib/api_stats_tracker.rb`)
- **Responsibility**: API usage monitoring with session tracking
- Tracks API calls by user, session, solution, table, method, endpoint
- Persists statistics to SQLite database (shares database with cache layer)
- Session tracking: Each client instance gets unique session_id
- Hashes API keys for privacy (SHA256, first 8 chars)
- Operates silently - never interrupts user work on errors

**DateFormatter** (`lib/smartsuite/date_formatter.rb`)
- **Responsibility**: UTC to local time conversion for user-friendly display
- SmartSuite stores all dates in UTC; this module converts them for display
- **Handles SmartSuite's `include_time` flag** to distinguish date-only vs datetime:
  - `include_time: false` → Date-only field (e.g., due date without time)
    - Returns calendar date WITHOUT timezone conversion: "2025-02-01"
    - Prevents "Feb 1" from becoming "Jan 31" due to timezone shift
  - `include_time: true` → Datetime field (e.g., meeting at specific time)
    - Converts to local timezone: "2025-02-04 03:15:00 -0800"
- Timezone configuration (priority order):
  1. Programmatic: `SmartSuite::DateFormatter.timezone = '-0500'`
  2. Environment: `SMARTSUITE_TIMEZONE=+0530` or `SMARTSUITE_TIMEZONE=utc`
  3. System `TZ` variable (Ruby respects this automatically)
  4. System default (operating system's local timezone)
- Special values: `:utc` (no conversion), `:local`/`:system` (use system tz)
- `to_local(value)`: Convert timestamp string OR date hash with include_time flag
- `convert_all(data)`: Recursively convert timestamps in hash/array structures
- `date_hash?(hash)`: Check if hash has date + include_time structure
- `timestamp?(str)`: Check if string is ISO 8601 timestamp
- `timezone_info`: Return current timezone configuration details
- Integrated into ResponseFormatter for automatic conversion in all responses

## Key Design Patterns

### SQLite Caching Strategy
The server uses aggressive caching to minimize API calls and enable efficient local queries:

1. **Aggressive Fetch**: When cache misses, fetch ALL records from table (paginated with limit=1000)
2. **Dynamic Tables**: One SQL table per SmartSuite table with proper column types
3. **Table-based TTL**: All records in a table expire together (default: 4 hours)
4. **No Mutation Invalidation**: Cache expires naturally by TTL, not invalidated on create/update/delete
5. **Local Querying**: Query cached data with flexible filters (SmartSuite API filters only used when cache disabled)
6. **Session Tracking**: Every client session tracked for usage analysis

### Token Optimization Strategy
This server is heavily optimized to minimize Claude's token usage:

1. **Filtered Table Structures**: `get_table` returns only essential fields (slug, label, field_type, minimal params), removing 83.8% of UI/display metadata
2. **TOON Format (Default)**: `list_records` uses TOON (Token-Oriented Object Notation) format by default (~50-60% savings vs JSON)
   - Tabular format for uniform arrays eliminates repetitive field names
   - Alternative format available: `:json` (standard JSON output)
3. **Required Field Selection**: `list_records` requires explicit `fields` parameter to prevent returning all columns
4. **No Truncation**: Fields returned in full (user must specify only needed fields to control tokens)
5. **Total vs Filtered Counts**: Always shows "X of Y total records" to help AI make informed decisions
6. **Cache-First Strategy**: Minimize API calls by querying local SQLite cache

### Data Flow Pattern
```
User Request (stdin)
    ↓
SmartSuiteServer.handle_request()
    ↓
ToolRegistry/PromptRegistry (MCP layer)
    ↓
SmartSuiteServer.handle_tool_call()
    ↓
SmartSuiteClient (includes modules):
  - Cache::Layer (check cache validity via Cache::Metadata, Cache::Performance)
      ├─ Cache HIT → Cache::Query SQLite → Return results
      └─ Cache MISS → Fetch ALL records → Cache → Query → Return
  - HttpClient.api_request()  ←  ApiStatsTracker.track_api_call()
  - WorkspaceOperations/TableOperations/RecordOperations/FieldOperations/MemberOperations/CommentOperations/ViewOperations
  - ResponseFormatter.filter_*()
    ↓                                          ↓
SmartSuite API                           Save to ~/.smartsuite_mcp_cache.db
    ↓                                    (both cache + API stats)
Response Filtering (plain text, no truncation)
    ↓
JSON-RPC Response (stdout)
```

### Error Handling Layers
- **Server Layer**: JSON-RPC protocol errors (code -32700, -32600, etc.)
- **Client Layer**: HTTP errors from SmartSuite API
- **Tracker Layer**: Silent failures with stderr logging

## Important Implementation Details

### Environment Variables
Always required:
- `SMARTSUITE_API_KEY`: SmartSuite API authentication
- `SMARTSUITE_ACCOUNT_ID`: Workspace identifier

Optional (timezone configuration):
- `SMARTSUITE_USER_EMAIL`: Your SmartSuite email for automatic timezone detection from your profile
- `SMARTSUITE_TIMEZONE`: Manual timezone override (e.g., `America/Mexico_City` or `+0530`)

### SmartSuite API Parameter Conventions
The SmartSuite API requires specific parameter placement:

**Query Parameters (in URL):**
- `limit`: Maximum number of records/items to return (POST endpoints)
- `offset`: Pagination offset (number of items to skip) (POST endpoints)
- `fields`: Field slug to include in response (GET endpoints, can be repeated)
- `solution`: Solution ID to filter by (GET endpoints)

**Body Parameters (JSON payload):**
- `filter`: Filter criteria object (POST endpoints)
- `sort`: Sort criteria array (POST endpoints)

**Example Endpoints:**
- List records: `POST /api/v1/applications/{table_id}/records/list/?limit=10&offset=0`
  - Body: `{"filter": {...}, "sort": [...]}`
- List members: `POST /api/v1/members/list/?limit=100&offset=0`
- List teams: `POST /api/v1/teams/list/?limit=1000&offset=0`
- List tables: `GET /api/v1/applications/?solution=sol_123&fields=name&fields=id&fields=structure`

**Important Notes:**
- The endpoints for members and teams are `/members/list/` and `/teams/list/`, NOT `/applications/members/records/list/`
- The `fields` parameter in GET endpoints (like `/applications/`) can be repeated to request multiple fields
- When `fields` is specified in `list_tables`, the API returns only those fields; when omitted, client-side filtering returns only essential fields (id, name, solution_id)
- The `/solutions/` endpoint does NOT respect the `fields` parameter - it always returns all fields. The `list_solutions` tool implements client-side filtering when `fields` parameter is provided
- Note: Requesting `permissions` field for all solutions (110+) may exceed token limits due to large permissions objects. Consider fetching individual solutions or using `include_activity_data` instead

### MCP Protocol Methods
The server implements:
- `initialize`: MCP handshake and capability negotiation
- `tools/list`: List all available SmartSuite tools
- `tools/call`: Execute a tool (list_solutions, analyze_solution_usage, list_solutions_by_owner, list_tables, get_table, create_table, list_records, get_record, create_record, update_record, delete_record, bulk_add_records, bulk_update_records, bulk_delete_records, attach_file, get_file_url, list_deleted_records, restore_deleted_record, add_field, bulk_add_fields, update_field, delete_field, list_members, search_member, list_teams, get_team, list_comments, add_comment, get_view_records, create_view, get_api_stats, reset_api_stats, get_cache_status, refresh_cache, convert_markdown_to_smartdoc)
- `prompts/list`: List example prompts for filters
- `prompts/get`: Get specific prompt templates
- `resources/list`: List available resources (empty)

### Solution Usage Analysis

The server provides powerful tools for identifying unused or underutilized solutions:

**analyze_solution_usage** - Analyzes all solutions and categorizes them by usage level based on `last_access` timestamps:
- **Inactive solutions**: Never accessed or not accessed in X days + minimal records/automations
- **Potentially unused**: Never accessed but has content, OR not accessed in X days with significant content
- **Active solutions**: Recently accessed (accessed within the threshold period)

**Important Notes:**
- The analysis focuses on `last_access` dates as the primary indicator of usage
- The `has_demo_data` flag is NOT used for categorization - many production solutions contain demo data
- "Never accessed" solutions may be templates, abandoned projects, or API-only solutions
- Solutions with high record counts but old `last_access` dates may indicate:
  - Automated data entry via API (not reflected in `last_access`)
  - Data repositories that are written to but rarely viewed
  - Archived/historical data still in use

Parameters:
- `days_inactive` (default: 90): Days since last access to consider inactive
- `min_records` (default: 10): Minimum records to not be considered empty

Returns:
```json
{
  "analysis_date": "2025-01-05T...",
  "thresholds": {"days_inactive": 90, "min_records": 10},
  "summary": {
    "total_solutions": 110,
    "inactive_count": 15,
    "potentially_unused_count": 8,
    "active_count": 87
  },
  "inactive_solutions": [...],
  "potentially_unused_solutions": [...]
}
```

Each solution includes:
- `id`, `name`, `status`, `hidden`
- `last_access`, `days_since_access`
- `records_count`, `members_count`, `applications_count`, `automation_count`
- `has_demo_data`
- `reason`: Why it's categorized as inactive/potentially unused

**list_solutions** - Now accepts optional parameters:
- `include_activity_data: true`: Include all activity/usage fields for custom analysis
- `fields: ["id", "name", ...]`: Request specific fields (client-side filtered since API doesn't support it)

**list_solutions_by_owner** - Filters solutions by owner:
- Fetches all solutions with permissions data
- Filters client-side by owner ID from `permissions.owners` array
- Returns only solutions owned by the specified user
- Accepts `include_activity_data: true` for usage metrics
- Much more efficient than requesting `permissions` field for all solutions

**get_solution_most_recent_record_update** - Gets most recent record update:
- Queries all tables in a solution
- Finds the most recently updated record across all tables
- Returns `last_updated.on` timestamp or nil if no records
- Useful for determining if a solution has recent data activity even without UI access

### Record Listing Behavior

**list_records** uses cache-first strategy with required fields parameter:

**Parameters:**
- `table_id` (required): Table identifier
- `limit` (default: 10): Maximum records to return
- `offset` (default: 0): Pagination offset
- `filter` (optional): Filter criteria to select records (SmartSuite filter format)
- `sort` (optional): Sort criteria (array of {field, direction} pairs)
- `fields` (required): Array of field slugs to return (e.g., `['status', 'priority']`)
- `hydrated` (default: true): Fetch human-readable values for linked records, users, etc.
- `format` (default: `:toon`): Output format - `:toon` (TOON, ~50-60% savings) or `:json`

**Behavior:**
- Filters, sorts, limits, and offsets work consistently regardless of cache state
- Returns TOON format by default showing "X of Y filtered records (Z total)" with tabular data
- When cache is enabled (default), uses local SQLite queries for zero-latency filtering/sorting
- When cache is disabled, sends filters/sort to SmartSuite API

**Implementation Details (for Claude Code):**
- **Cache enabled**: Filters → SQL WHERE, Sort → SQL ORDER BY, then limit/offset
- **Cache disabled**: All parameters sent to SmartSuite API
- Cache is automatically populated on first access and expires after TTL (default 4 hours)
- Mutations (create/update/delete) do NOT invalidate cache - it expires naturally

**Important Notes:**
- **Fields parameter is REQUIRED** - returns error if not specified
- **No value truncation** - returns full field values (control tokens by specifying only needed fields)
- **Always shows total vs filtered counts** - helps AI make informed pagination decisions

**Example:**
```ruby
# Default usage - TOON format (most token-efficient)
list_records('tbl_123', 10, 0, fields: ['status', 'priority', 'assigned_to'])

# Explicit format selection
list_records('tbl_123', 10, 0, fields: ['status'], format: :toon)
list_records('tbl_123', 10, 0, fields: ['status'], format: :json)

# Returns error - missing fields
list_records('tbl_123', 10, 0)  # ERROR
```

### Available Prompt Templates
The PromptRegistry provides 8 example prompts demonstrating common filter patterns:

1. **filter_active_records**: Single select/status filtering (uses `is` operator)
2. **filter_by_date_range**: Date range filtering (uses special date object format)
3. **list_tables_by_solution**: Simple solution-based filtering
4. **filter_records_contains_text**: Text search (uses `contains` operator)
5. **filter_by_linked_record**: Linked record filtering (uses `has_any_of` with record IDs) ⚠️ Common pitfall: NOT `is`
6. **filter_by_numeric_range**: Numeric range filtering (uses `is_equal_or_greater_than`, `is_equal_or_less_than`)
7. **filter_by_multiple_select**: Multiple select/tag filtering (uses `has_any_of`, `has_all_of`, or `is_exactly`)
8. **filter_by_assigned_user**: User field filtering (uses `has_any_of` with user IDs)

Each prompt generates a complete example with the correct filter structure, operators, and value format for that field type.

### SmartSuite Filter Syntax

**Note:** SmartSuite API filters are only used when cache is disabled. When using cache (default), all filtering is done locally on cached records via SQL queries.

#### Filter Operators by Field Type

**Text-based fields** (Text, Email, Phone, Full Name, Address, Link, Text Area, etc.):
- Operators: `is`, `is_not`, `is_empty`, `is_not_empty`, `contains`, `not_contains`
- Value: String
```ruby
{"field" => "email", "comparison" => "contains", "value" => "example.com"}
```

**Numeric fields** (Number, Currency, Rating, Percent, Duration, etc.):
- Operators: `is_equal_to`, `is_not_equal_to`, `is_greater_than`, `is_less_than`, `is_equal_or_greater_than`, `is_equal_or_less_than`, `is_empty`, `is_not_empty`
- Value: Numeric
```ruby
{"field" => "amount", "comparison" => "is_greater_than", "value" => 1000}
```

**Date fields** (Date, Due Date, Date Range, First Created, Last Updated):
- Operators: `is`, `is_not`, `is_before`, `is_on_or_before`, `is_on_or_after`, `is_empty`, `is_not_empty`
- Special for Due Date: `is_overdue`, `is_not_overdue`
- Value: Date object with `date_mode` and `date_mode_value`
```ruby
{
  "field" => "due_date",
  "comparison" => "is_on_or_after",
  "value" => {
    "date_mode" => "exact_date",
    "date_mode_value" => "2025-01-01"
  }
}
```

**Single Select/Status fields**:
- Operators: `is`, `is_not`, `is_any_of`, `is_none_of`, `is_empty`, `is_not_empty`
- Value: String or array
```ruby
{"field" => "status", "comparison" => "is_any_of", "value" => ["Active", "Pending"]}
```

**Multiple Select/Tag fields**:
- Operators: `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`
- Value: Array
```ruby
{"field" => "tags", "comparison" => "has_any_of", "value" => ["urgent", "bug"]}
```

**Linked Record fields**:
- Operators: `contains`, `not_contains`, `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`
- Value: Array of record IDs (use null for empty checks)
```ruby
{"field" => "related_project", "comparison" => "has_any_of", "value" => ["record_id_1", "record_id_2"]}
{"field" => "related_project", "comparison" => "is_empty", "value" => nil}
```

**Assigned To (User) fields**:
- Operators: `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`
- Value: Array of user IDs
```ruby
{"field" => "assigned_user", "comparison" => "has_any_of", "value" => ["user_id_1"]}
```

**Files & Images**:
- Operators: `file_name_contains`, `file_type_is`, `is_empty`, `is_not_empty`
- Value: String (filename or file type)
- Valid file types: archive, image, music, pdf, powerpoint, spreadsheet, video, word, other
```ruby
{"field" => "attachments", "comparison" => "file_type_is", "value" => "pdf"}
```

**Yes/No (Boolean)**:
- Operators: `is`, `is_empty`, `is_not_empty`
- Value: Boolean or null

**Important notes:**
- Filter operators are case-sensitive
- For empty checks, use `nil` or `null` as value
- Date Range fields reference dates as `[field_slug].from_date` and `[field_slug].to_date`
- Formula and Lookup fields inherit operators from their return types

### Response Filtering in ResponseFormatter
The `filter_field_structure` method aggressively removes non-essential data:
- Keeps: slug, label, field_type, required, unique, primary, choices (minimal), linked_application, entries_allowed
- Removes: display_format, help_doc, default_value, width, column_widths, visible_fields, choice colors/icons, etc.

The `truncate_value` method **does NOT truncate values** (per user request):
- Returns all field values in full without truncation
- Users must specify only needed fields via `fields` parameter to control token usage
- Encourages fetching minimal fields rather than truncating large values

## Testing Approach

Tests use Minitest (Ruby stdlib). Structure:
- Mock stdin/stdout using StringIO
- Test MCP protocol compliance
- Verify tool handlers work correctly
- Validate API tracking functionality
- Check error handling

When adding tests:
1. Create methods starting with `test_`
2. Use `call_private_method` helper for internal methods
3. Mock HTTP responses for API tests
4. Verify both success and error cases

### Field Operations

The server supports full CRUD operations on table fields via the FieldOperations module (`lib/smartsuite/api/field_operations.rb`):

**add_field** (line 19):
- Endpoint: `POST /api/v1/applications/{table_id}/add_field/`
- Always includes `field_position` (defaults to `{}`) and `auto_fill_structure_layout` (defaults to `true`)
- Handles empty API responses (returns `{}` on success)

**bulk_add_fields** (line 46):
- Endpoint: `POST /api/v1/applications/{table_id}/bulk-add-fields/`
- Add multiple fields in one request for better performance
- Note: Certain field types not supported (Formula, Count, TimeTracking)

**update_field** (line 70):
- Endpoint: `PUT /api/v1/applications/{table_id}/change_field/`
- Automatically merges slug into field_data body
- Uses PUT HTTP method

**delete_field** (line 92):
- Endpoint: `POST /api/v1/applications/{table_id}/delete_field/`
- Returns deleted field object on success
- Operation is permanent

**Help Text Format:**
The `help_doc` parameter requires rich text format (TipTap/ProseMirror):
```ruby
{
  "data" => {
    "type" => "doc",
    "content" => [
      {
        "type" => "paragraph",
        "content" => [{"type" => "text", "text" => "Help text"}]
      }
    ]
  },
  "html" => "<p>Help text</p>",
  "preview" => "Help text"
}
```

Display format can be `"tooltip"` (hover to see) or `"inline"` (shown below field name).

### Comment Operations

The server supports comment management via the CommentOperations module (`lib/smartsuite/api/comment_operations.rb`):

**list_comments** (line 15):
- Endpoint: `GET /api/v1/comments/?record=[Record_Id]`
- Returns array of comment objects with message content, author, timestamps, and assignment information
- Query parameter: `record` (the record ID)

**add_comment** (line 36):
- Endpoint: `POST /api/v1/comments/`
- Creates a new comment on a record
- Supports plain text input (automatically formatted to rich text)
- Optional comment assignment to users via `assigned_to` parameter

**Message Format:**
Comments use SmartSuite's rich text format (TipTap/ProseMirror). Plain text is automatically converted:
```ruby
# Input (plain text)
"This is a comment"

# Automatically formatted to:
{
  "data" => {
    "type" => "doc",
    "content" => [
      {
        "type" => "paragraph",
        "content" => [
          {
            "type" => "text",
            "text" => "This is a comment"
          }
        ]
      }
    ]
  }
}
```

**Comment Object Structure:**
- `id`: Comment unique identifier
- `message`: Rich text message object with data, html, and preview
- `record`: Record ID the comment belongs to
- `application`: Table/app ID
- `solution`: Solution ID
- `member`: User ID of comment creator
- `created_on`: Timestamp
- `assigned_to`: Optional assigned user ID
- `followers`: Array of user IDs following the comment
- `reactions`: Array of emoji reactions
- `key`: Comment number on the record

**Important Notes:**
- Endpoint paths must NOT include `/api/v1/` prefix as HttpClient already prepends the base URL
- The API expects query parameter named `record`, not `record_id` (though the MCP tool parameter can use any name)

### SmartDoc Format (Rich Text Fields)

SmartSuite rich text fields (`richtextareafield`) use **TipTap/ProseMirror format but with snake_case type names** instead of the standard camelCase.

**CRITICAL: Use snake_case for all type names:**

| Standard TipTap (camelCase) | SmartSuite (snake_case) |
|-----------------------------|-------------------------|
| `bulletList`                | `bullet_list`           |
| `orderedList`               | `ordered_list`          |
| `listItem`                  | `list_item`             |
| `checkList`                 | `check_list`            |
| `checkListItem`             | `check_list_item`       |
| `tableRow`                  | `table_row`             |
| `tableCell`                 | `table_cell`            |
| `tableHeader`               | `table_header`          |
| `codeBlock`                 | `code_block`            |
| `hardBreak`                 | `hard_break`            |
| `horizontalRule`            | `horizontal_rule`       |

**Types that remain the same:** `doc`, `paragraph`, `heading`, `text`, `table`, `image`, `mention`, `callout`, `attachment`

**Marks (inline formatting):** `strong` (bold), `em` (italic), `underline`, `strikethrough`, `link`, `color`, `highlight`

**Basic structure:**
```json
{
  "data": {
    "type": "doc",
    "content": [
      {
        "type": "heading",
        "attrs": {"level": 2},
        "content": [{"type": "text", "text": "Title"}]
      },
      {
        "type": "bullet_list",
        "content": [
          {
            "type": "list_item",
            "content": [
              {
                "type": "paragraph",
                "content": [{"type": "text", "text": "Item 1"}]
              }
            ]
          }
        ]
      }
    ]
  }
}
```

For complete examples including tables, code blocks, callouts, mentions, and more, see `docs/smartdoc_examples.md`.

### Markdown to SmartDoc Conversion

The server provides a `convert_markdown_to_smartdoc` tool that converts Markdown text to SmartDoc format.

**Supported Markdown Features:**
- Headings: `# H1`, `## H2`, `### H3`
- Bold: `**text**` or `__text__`
- Italic: `*text*` or `_text_`
- Bullet lists: `- item` or `* item`
- Tables: `| col1 | col2 |`

**Usage Pattern for Batch Updates (optimized for API efficiency):**

1. Fetch records with markdown content:

    ```ruby
    records = list_records(table_id, 100, 0,
      filter: { operator: 'and', fields: [{ field: 'status', comparison: 'is', value: 'pending' }] },
      fields: ['id', 'description']
    )
    ```

1. Convert markdown fields and prepare update batch:

    ```ruby
    updates = records.map do |record|
      smartdoc = convert_markdown_to_smartdoc(record['description'])
      { 'id' => record['id'], 'description' => smartdoc }
    end
    ```

1. Bulk update with converted SmartDoc (single API call):

    ```ruby
    bulk_update_records(table_id, updates)
    ```

**Implementation:** `SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_string)`

## Logging and Metrics

### Unified Logging System

The server uses a unified logging system (`SmartSuite::Logger`) that consolidates all logging into a single configurable class:

**Log File:**
- Production: `~/.smartsuite_mcp.log`
- Test: `~/.smartsuite_mcp_test.log`
- Integration tests: `~/.smartsuite_mcp_integration.log`

**Features:**
- Multiple log levels: DEBUG, INFO, WARN, ERROR
- Log categories: API, DB, CACHE, S3, SERVER, METRIC
- ANSI color support (configurable via `colors_enabled`)
- Daily log rotation
- Configurable via environment variables

**Environment Variables:**
- `SMARTSUITE_LOG_LEVEL`: Set log level (debug, info, warn, error)
- `SMARTSUITE_LOG_STDERR`: Set to 'true' to also output to stderr

**Usage:**
```ruby
SmartSuite::Logger.info('Server started')
SmartSuite::Logger.api_request(:get, url, params)
SmartSuite::Logger.cache('hit', table_id, details)
SmartSuite::Logger.error('Failed', error: exception)
```

**Database File:**
- `~/.smartsuite_mcp_cache.db`: SQLite database containing:
  - Cached table records (one SQL table per SmartSuite table)
  - API call logs with session tracking
  - API statistics summaries
  - Cache metadata (TTL config, table schemas)

## SmartSuite API Rate Limits

Be aware of:
- Standard: 5 requests/second per user
- Overage: 2 requests/second when exceeding monthly allowance
- Hard limit: Requests denied at 125% of monthly limits

## Dependencies

Ruby standard library:
- json
- net/http
- uri
- time
- fileutils
- digest

External gems:
- sqlite3 (caching layer)
- toon-ruby (TOON format encoding for token optimization)

Test dependencies:
- minitest
- rake
