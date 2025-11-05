# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Model Context Protocol (MCP) server for SmartSuite, written in Ruby. It enables AI assistants to interact with SmartSuite workspaces through the MCP protocol via stdin/stdout communication.

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

- **ToolRegistry** (`tool_registry.rb`, 344 lines): All 15 tool schemas organized by category
- **PromptRegistry** (`prompt_registry.rb`, 447 lines): 8 prompt templates covering all major filter patterns
- **ResourceRegistry** (`resource_registry.rb`, 15 lines): Resource listing (currently empty)

### 3. API Client Layer (`lib/smartsuite/api/`)
Handles SmartSuite API communication:

- **HttpClient** (`http_client.rb`, 68 lines): HTTP request execution, authentication, logging
- **DataOperations** (`data_operations.rb`, 159 lines): Solutions and tables management
- **RecordOperations** (`record_operations.rb`, 114 lines): Record CRUD operations
- **FieldOperations** (`field_operations.rb`, 103 lines): Table schema management
- **MemberOperations** (`member_operations.rb`, 212 lines): User and team management

**SmartSuiteClient** (`lib/smartsuite_client.rb`, 30 lines)
- Thin wrapper that includes all API modules
- 30 lines vs original 708 lines (96% reduction)

### 4. Formatters Layer (`lib/smartsuite/formatters/`)
Implements token optimization:

- **ResponseFormatter** (`response_formatter.rb`, 211 lines): Response filtering, plain text formatting, truncation strategies

### 5. Supporting Components
**ApiStatsTracker** (`lib/api_stats_tracker.rb`)
- **Responsibility**: API usage monitoring and persistence
- Tracks API calls by user, solution, table, method, endpoint
- Persists statistics to `~/.smartsuite_mcp_stats.json`
- Hashes API keys for privacy (SHA256, first 8 chars)
- Operates silently - never interrupts user work on errors

## Key Design Patterns

### Token Optimization Strategy
This server is heavily optimized to minimize Claude's token usage:

1. **Filtered Table Structures**: `get_table` returns only essential fields (slug, label, field_type, minimal params), removing 83.8% of UI/display metadata
2. **Plain Text Responses**: `list_records` returns formatted text instead of JSON (30-50% savings)
3. **Summary Mode**: `list_records` with `summary_only: true` returns statistics instead of data
4. **Field Selection**: `list_records` requires explicit `fields` parameter to prevent returning all columns
5. **Solution Filtering**: `list_members` accepts `solution_id` to filter server-side
6. **Automatic Limiting**: `list_records` caps to 2 records when no filter is provided

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
  - HttpClient.api_request()  ←  ApiStatsTracker.track_api_call()
  - DataOperations/RecordOperations/FieldOperations/MemberOperations
  - ResponseFormatter.filter_*()
    ↓                                          ↓
SmartSuite API                           Save to ~/.smartsuite_mcp_stats.json
    ↓
Response Filtering (token optimization)
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

### MCP Protocol Methods
The server implements:
- `initialize`: MCP handshake and capability negotiation
- `tools/list`: List all available SmartSuite tools
- `tools/call`: Execute a tool (list_solutions, list_tables, get_table, list_records, create_record, update_record, delete_record, add_field, bulk_add_fields, update_field, delete_field, list_members, get_api_stats, reset_api_stats)
- `prompts/list`: List example prompts for filters
- `prompts/get`: Get specific prompt templates
- `resources/list`: List available resources (empty)

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
The `filter_field_structure` method (`lib/smartsuite/formatters/response_formatter.rb:21`) aggressively removes non-essential data:
- Keeps: slug, label, field_type, required, unique, primary, choices (minimal), linked_application, entries_allowed
- Removes: display_format, help_doc, default_value, width, column_widths, visible_fields, choice colors/icons, etc.

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

## Logging and Metrics

Two separate log files:
- `~/.smartsuite_mcp_stats.json`: API usage statistics (persistent)
- `~/.smartsuite_mcp_metrics.log`: Tool calls and token usage (append-only)

Metrics are logged for every API call showing:
- Tool name
- Result summary
- Token estimate
- Running total

## SmartSuite API Rate Limits

Be aware of:
- Standard: 5 requests/second per user
- Overage: 2 requests/second when exceeding monthly allowance
- Hard limit: Requests denied at 125% of monthly limits

## Dependencies

Uses only Ruby standard library:
- json
- net/http
- uri
- time
- fileutils
- digest

Test dependencies:
- minitest
- rake
