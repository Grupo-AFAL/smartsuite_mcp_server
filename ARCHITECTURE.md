# SmartSuite MCP Server Architecture

## Overview

The SmartSuite MCP Server is organized into a modular architecture with clear separation of concerns.

## File Structure

```
smartsuite_mcp/
├── smartsuite_server.rb      # Main MCP server (339 lines)
├── lib/
│   ├── smartsuite_client.rb  # SmartSuite API client (126 lines)
│   └── api_stats_tracker.rb  # API statistics tracking (131 lines)
├── test/
│   └── test_smartsuite_server.rb
├── Gemfile
├── Rakefile
└── README.md
```

## Component Responsibilities

### SmartSuiteServer (smartsuite_server.rb)

**Purpose:** MCP protocol handler and main entry point

**Responsibilities:**
- Handle JSON-RPC protocol communication (stdin/stdout)
- Process MCP protocol methods (initialize, tools/list, tools/call, etc.)
- Route tool calls to appropriate components
- Manage error handling and responses
- Handle notifications

**Key Methods:**
- `run()` - Main event loop
- `handle_request()` - Route MCP protocol methods
- `handle_initialize()` - MCP initialization
- `handle_tools_list()` - List available tools
- `handle_tool_call()` - Execute tool calls

### SmartSuiteClient (lib/smartsuite_client.rb)

**Purpose:** SmartSuite API interaction layer

**Responsibilities:**
- Execute HTTP requests to SmartSuite API
- Format and filter API responses
- Reduce response sizes to meet MCP limits
- Integrate with statistics tracker

**Key Methods:**
- `list_solutions()` - Get workspace solutions
- `get_solution()` - Get single solution details (includes member_ids)
- `list_members()` - Get workspace members/users (supports solution filtering)
- `list_tables()` - Get workspace tables
- `list_records()` - Query table records
- `get_record()` - Get specific record
- `create_record()` - Create new record
- `update_record()` - Update existing record
- `delete_record()` - Delete a record
- `api_request()` - Private HTTP client

**Features:**
- Automatic response filtering to reduce size
- Handles both hash and array response formats
- Optional stats tracking integration

### ApiStatsTracker (lib/api_stats_tracker.rb)

**Purpose:** API usage monitoring and tracking

**Responsibilities:**
- Track all API calls by various dimensions
- Persist statistics to disk
- Generate usage reports
- Extract metadata from API endpoints

**Key Methods:**
- `track_api_call()` - Record an API call
- `get_stats()` - Retrieve current statistics
- `reset_stats()` - Clear all statistics
- `extract_ids_from_endpoint()` - Parse solution/table IDs

**Tracking Dimensions:**
- Total calls
- By user (hashed API key)
- By HTTP method (GET, POST, PATCH, DELETE)
- By SmartSuite solution
- By SmartSuite table
- By API endpoint
- First and last call timestamps

**Storage:**
- File: `~/.smartsuite_mcp_stats.json`
- Format: JSON
- Persistence: Automatic on each call

## Data Flow

### Tool Call Flow

```
User Request (stdin)
    ↓
SmartSuiteServer.run()
    ↓
SmartSuiteServer.handle_tool_call()
    ↓
SmartSuiteClient.list_solutions()  ←  ApiStatsTracker.track_api_call()
    ↓                                          ↓
SmartSuite API                           Save to ~/.smartsuite_mcp_stats.json
    ↓
Response Filtering
    ↓
JSON-RPC Response
    ↓
User (stdout)
```

### Statistics Flow

```
API Call
    ↓
SmartSuiteClient.api_request()
    ↓
ApiStatsTracker.track_api_call()
    ↓
├─ Increment counters
├─ Extract solution/table IDs
├─ Update timestamps
└─ Save to disk
```

## Design Decisions

### 1. Separation of Concerns

- **Server**: Only handles MCP protocol
- **Client**: Only handles SmartSuite API
- **Tracker**: Only handles statistics

This makes testing easier and allows components to be reused or modified independently.

### 2. Optional Stats Tracking

The `SmartSuiteClient` accepts an optional `stats_tracker` parameter, allowing it to work with or without tracking. This makes it more flexible and testable.

### 3. Response Filtering

The client automatically filters API responses to include only essential fields, preventing MCP 1MB limit errors.

### 4. Error Handling

Each layer handles its own errors:
- Server: JSON-RPC protocol errors
- Client: HTTP errors
- Tracker: Silent failures (doesn't interrupt user work)

### 5. Testability

All components can be tested independently:
- Server: Test MCP protocol handling
- Client: Test API calls with mocks
- Tracker: Test statistics logic

## Benefits of This Architecture

1. **Maintainability**: Each file has a single, clear purpose
2. **Testability**: Components can be tested in isolation
3. **Reusability**: Client and tracker can be used in other projects
4. **Scalability**: Easy to add new tools or tracking dimensions
5. **Debugging**: Easier to locate and fix issues
6. **Documentation**: Clear structure makes code easier to understand

## Future Enhancements

Potential improvements that benefit from this architecture:

1. **Caching Layer**: Add between server and client
2. **Rate Limiting**: Implement in client to respect SmartSuite limits
3. **Webhook Support**: Add new component for push notifications
4. **Multiple Backends**: Support other project management tools
5. **Advanced Stats**: Add performance metrics, error tracking
