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

The codebase follows a three-layer modular architecture with clear separation of concerns:

### 1. SmartSuiteServer (`smartsuite_server.rb`)
- **Responsibility**: MCP protocol handler and main entry point
- Manages JSON-RPC communication over stdin/stdout
- Routes MCP protocol methods (initialize, tools/list, tools/call, prompts/list, resources/list)
- Handles errors and notifications
- Does NOT handle SmartSuite API calls directly

### 2. SmartSuiteClient (`lib/smartsuite_client.rb`)
- **Responsibility**: SmartSuite API interaction layer
- Executes HTTP requests to SmartSuite API (`https://app.smartsuite.com/api/v1`)
- Implements aggressive response filtering to reduce token usage (83.8% reduction for table structures)
- Returns plain text format for record lists (30-50% token savings)
- Tracks token usage with metrics logging
- Does NOT handle MCP protocol

### 3. ApiStatsTracker (`lib/api_stats_tracker.rb`)
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
SmartSuiteServer.handle_tool_call()
    ↓
SmartSuiteClient.{method}()  ←  ApiStatsTracker.track_api_call()
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

### SmartSuite Filter Syntax
Date filters require special object format:
```ruby
{
  "field" => "due_date",
  "comparison" => "is_after",
  "value" => {
    "date_mode" => "exact_date",
    "date_mode_value" => "2025-01-01"
  }
}
```

Regular filters use simple values:
```ruby
{
  "field" => "status",
  "comparison" => "is",
  "value" => "active"
}
```

### Response Filtering in SmartSuiteClient
The `filter_field_structure` method aggressively removes non-essential data:
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

The server supports full CRUD operations on table fields:

**add_field** (`lib/smartsuite_client.rb:378`):
- Endpoint: `POST /api/v1/applications/{table_id}/add_field/`
- Always includes `field_position` (defaults to `{}`) and `auto_fill_structure_layout` (defaults to `true`)
- Handles empty API responses (returns `{}` on success)

**bulk_add_fields** (`lib/smartsuite_client.rb:396`):
- Endpoint: `POST /api/v1/applications/{table_id}/bulk-add-fields/`
- Add multiple fields in one request for better performance
- Note: Certain field types not supported (Formula, Count, TimeTracking)

**update_field** (`lib/smartsuite_client.rb:413`):
- Endpoint: `PUT /api/v1/applications/{table_id}/change_field/`
- Automatically merges slug into field_data body
- Uses PUT HTTP method

**delete_field** (`lib/smartsuite_client.rb:428`):
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
