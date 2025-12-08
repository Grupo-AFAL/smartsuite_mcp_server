# MCP Protocol Implementation

Deep dive into how SmartSuite MCP Server implements the Model Context Protocol.

## Overview

The Model Context Protocol (MCP) is a JSON-RPC 2.0-based protocol that enables AI assistants like Claude to interact with external tools and data sources. SmartSuite MCP Server implements MCP to bridge Claude with SmartSuite's REST API.

**Key aspects:**

- Transport: stdin/stdout
- Protocol: JSON-RPC 2.0
- Paradigm: Tools, Prompts, Resources
- Implementation: 100% Ruby standard library

---

## MCP Architecture

### Communication Flow

```
Claude Desktop App
      ↓
   MCP Client
      ↓ (JSON-RPC over stdin/stdout)
SmartSuite MCP Server
      ↓ (HTTPS REST API)
  SmartSuite API
```

### Protocol Layers

```
┌─────────────────────────────────────────┐
│    Application Layer (Claude)           │
│  - Natural language processing          │
│  - Tool selection & planning             │
│  - Response interpretation               │
└──────────────┬──────────────────────────┘
               │ MCP Protocol
┌──────────────┴──────────────────────────┐
│    MCP Client Layer (Claude Desktop)    │
│  - Tool/prompt/resource discovery        │
│  - JSON-RPC message formatting           │
│  - stdin/stdout communication            │
└──────────────┬──────────────────────────┘
               │ JSON-RPC 2.0
┌──────────────┴──────────────────────────┐
│   MCP Server Layer (SmartSuite Server)  │
│  - Protocol method routing               │
│  - Tool/prompt/resource registries       │
│  - Request/response handling             │
└──────────────┬──────────────────────────┘
               │ HTTP/REST
┌──────────────┴──────────────────────────┐
│      SmartSuite REST API                │
└─────────────────────────────────────────┘
```

---

## JSON-RPC 2.0 Protocol

### Message Format

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [...]
  }
}
```

**Error:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32600,
    "message": "Invalid Request"
  }
}
```

### Standard Error Codes

```ruby
PARSE_ERROR = -32700      # Invalid JSON
INVALID_REQUEST = -32600  # Malformed request
METHOD_NOT_FOUND = -32601 # Unknown method
INVALID_PARAMS = -32602   # Bad parameters
INTERNAL_ERROR = -32603   # Server error
```

---

## MCP Protocol Methods

### 1. Initialize

**Purpose:** Handshake and capability negotiation

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "roots": { "listChanged": true },
      "sampling": {}
    },
    "clientInfo": {
      "name": "claude-desktop",
      "version": "1.0.0"
    }
  }
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {},
      "prompts": {},
      "resources": {}
    },
    "serverInfo": {
      "name": "smartsuite-mcp-server",
      "version": "1.0.0"
    }
  }
}
```

**Implementation:**

```ruby
def handle_initialize(params)
  {
    protocolVersion: "2024-11-05",
    capabilities: {
      tools: {},
      prompts: {},
      resources: {}
    },
    serverInfo: {
      name: "smartsuite-mcp-server",
      version: "1.0.0"
    }
  }
end
```

### 2. Tools/List

**Purpose:** Discover available tools

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "list_solutions",
        "description": "List all solutions in workspace",
        "inputSchema": {
          "type": "object",
          "properties": {
            "fields": {
              "type": "array",
              "items": { "type": "string" },
              "description": "Optional: Array of field names to request"
            },
            "include_activity_data": {
              "type": "boolean",
              "description": "Optional: Include usage metrics"
            }
          },
          "required": []
        }
      }
    ]
  }
}
```

**Implementation:**

```ruby
def handle_tools_list
  {
    tools: ToolRegistry.all_tools
  }
end
```

### 3. Tools/Call

**Purpose:** Execute a tool

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "list_solutions",
    "arguments": {
      "fields": ["id", "name"],
      "include_activity_data": true
    }
  }
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "5 of 5 filtered (5 total)\nsolutions[5]{id|name|logo_icon|logo_color}:\nsol_abc123|Project Management|briefcase|blue\nsol_def456|Customer CRM|users|green\n..."
      }
    ],
    "isError": false
  }
}
```

**Implementation:**

```ruby
def handle_tools_call(name, arguments)
  result = execute_tool(name, arguments)

  {
    content: [
      {
        type: "text",
        text: result
      }
    ],
    isError: false
  }
rescue => e
  {
    content: [
      {
        type: "text",
        text: "Error: #{e.message}"
      }
    ],
    isError: true
  }
end
```

### 4. Prompts/List

**Purpose:** Discover available prompt templates

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "prompts/list",
  "params": {}
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "prompts": [
      {
        "name": "filter_active_records",
        "description": "Filter records by single select field (e.g., status = Active)",
        "arguments": [
          {
            "name": "table_id",
            "description": "Table identifier",
            "required": true
          }
        ]
      }
    ]
  }
}
```

### 5. Prompts/Get

**Purpose:** Get specific prompt template

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "prompts/get",
  "params": {
    "name": "filter_active_records",
    "arguments": {
      "table_id": "tbl_abc123"
    }
  }
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "description": "Filter records by single select field",
    "messages": [
      {
        "role": "user",
        "content": {
          "type": "text",
          "text": "Show me how to filter by status = Active..."
        }
      }
    ]
  }
}
```

### 6. Resources/List

**Purpose:** List available resources

**Request:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "resources/list",
  "params": {}
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "resources": []
  }
}
```

**Note:** Currently empty, extensibility point for future features.

---

## Tool Schema Design

### Tool Definition Structure

```ruby
{
  name: "list_records",
  description: "List records from a table with CACHE-FIRST strategy",
  inputSchema: {
    type: "object",
    properties: {
      table_id: {
        type: "string",
        description: "Table identifier (required)"
      },
      fields: {
        type: "array",
        items: { type: "string" },
        description: "REQUIRED: Array of field slugs to return"
      },
      limit: {
        type: "number",
        description: "Maximum records to return (default: 10)"
      },
      offset: {
        type: "number",
        description: "Pagination offset (default: 0)"
      },
      filter: {
        type: "object",
        description: "Optional: Filter criteria"
      }
    },
    required: ["table_id", "fields"]
  }
}
```

### Tool Categories

**Workspace Tools (3):**

- `list_solutions` - List solutions/workspaces
- `analyze_solution_usage` - Analyze inactive solutions
- `list_solutions_by_owner` - Filter by owner

**Table Tools (3):**

- `list_tables` - List tables in solution
- `get_table` - Get table structure
- `create_table` - Create new table

**Record Tools (4):**

- `list_records` - Query records (cache-first)
- `create_record` - Create record
- `update_record` - Update record
- `delete_record` - Delete record

**Field Tools (4):**

- `add_field` - Add single field
- `bulk_add_fields` - Add multiple fields
- `update_field` - Update field definition
- `delete_field` - Remove field

**Member Tools (4):**

- `list_members` - List workspace users
- `search_member` - Search by name/email
- `list_teams` - List teams
- `get_team` - Get team details

**Comment Tools (2):**

- `list_comments` - Get record comments
- `add_comment` - Add comment

**View Tools (2):**

- `get_view_records` - Query view
- `create_view` - Create new view

**Stats Tools (3):**

- `get_api_stats` - API usage statistics
- `reset_api_stats` - Clear statistics
- `get_solution_most_recent_record_update` - Check solution activity

**Total: 26 tools**

---

## Prompt Template Design

### Prompt Structure

```ruby
{
  name: "filter_active_records",
  description: "Filter records by single select field (e.g., status = Active)",
  arguments: [
    {
      name: "table_id",
      description: "Table identifier",
      required: true
    }
  ]
}
```

### Prompt Template Format

```ruby
def generate_prompt(name, arguments)
  {
    description: "Description of pattern",
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: "Example query with explanation..."
        }
      }
    ]
  }
end
```

### Available Prompts (8)

1. **filter_active_records** - Single select filtering
2. **filter_by_date_range** - Date range queries
3. **list_tables_by_solution** - Solution filtering
4. **filter_records_contains_text** - Text search
5. **filter_by_linked_record** - Linked record filtering
6. **filter_by_numeric_range** - Numeric ranges
7. **filter_by_multiple_select** - Tag/multiple select
8. **filter_by_assigned_user** - User assignment

---

## Request/Response Flow

### Successful Tool Call

```
1. Claude sends tool call:
   method: "tools/call"
   params: {name: "list_solutions", arguments: {...}}

2. Server receives via stdin:
   parse_json()

3. Route to handler:
   handle_tools_call("list_solutions", {...})

4. Execute tool:
   SmartSuiteClient.list_solutions(...)

5. Format response:
   ResponseFormatter.format_solutions(...)

6. Return result:
   {content: [{type: "text", text: "..."}], isError: false}

7. Send to Claude via stdout:
   send_response({jsonrpc: "2.0", id: X, result: {...}})
```

### Error Handling

```
1. Claude sends invalid request:
   method: "invalid/method"

2. Server catches error:
   rescue => e

3. Generate error response:
   {
     jsonrpc: "2.0",
     id: X,
     error: {
       code: -32601,
       message: "Method not found: invalid/method"
     }
   }

4. Send to Claude via stdout
```

---

## Implementation Details

### Server Layer (`smartsuite_server.rb`)

**Main Loop:**

```ruby
def run
  loop do
    line = $stdin.gets
    break if line.nil?

    request = JSON.parse(line, symbolize_names: true)
    response = handle_request(request)
    send_response(response)
  end
end
```

**Request Router:**

```ruby
def handle_request(request)
  case request[:method]
  when "initialize"
    handle_initialize(request[:params])
  when "tools/list"
    handle_tools_list
  when "tools/call"
    handle_tools_call(request[:params][:name], request[:params][:arguments])
  when "prompts/list"
    handle_prompts_list
  when "prompts/get"
    handle_prompts_get(request[:params][:name], request[:params][:arguments])
  when "resources/list"
    handle_resources_list
  else
    raise "Method not found: #{request[:method]}"
  end
rescue => e
  error_response(request[:id], e)
end
```

### Tool Registry (`lib/smart_suite/mcp/tool_registry.rb`)

**Organization:**

```ruby
module ToolRegistry
  WORKSPACE_TOOLS = [...]
  TABLE_TOOLS = [...]
  RECORD_TOOLS = [...]
  FIELD_TOOLS = [...]
  MEMBER_TOOLS = [...]
  COMMENT_TOOLS = [...]
  VIEW_TOOLS = [...]
  STATS_TOOLS = [...]

  def self.all_tools
    WORKSPACE_TOOLS + TABLE_TOOLS + RECORD_TOOLS +
    FIELD_TOOLS + MEMBER_TOOLS + COMMENT_TOOLS +
    VIEW_TOOLS + STATS_TOOLS
  end
end
```

**Tool Schema:**

```ruby
{
  name: "list_solutions",
  description: "List all solutions in workspace",
  inputSchema: {
    type: "object",
    properties: {
      fields: {
        type: "array",
        items: { type: "string" },
        description: "Optional: Field names to return"
      },
      include_activity_data: {
        type: "boolean",
        description: "Optional: Include usage metrics"
      }
    },
    required: []
  }
}
```

### Prompt Registry (`lib/smart_suite/mcp/prompt_registry.rb`)

**Prompt Categories:**

```ruby
module PromptRegistry
  FILTER_PROMPTS = [
    filter_active_records,
    filter_by_date_range,
    filter_records_contains_text,
    filter_by_linked_record,
    filter_by_numeric_range,
    filter_by_multiple_select,
    filter_by_assigned_user
  ]

  LISTING_PROMPTS = [
    list_tables_by_solution
  ]

  def self.all_prompts
    FILTER_PROMPTS + LISTING_PROMPTS
  end
end
```

---

## Protocol Extensions

### Custom Capabilities

**Server capabilities:**

```json
{
  "capabilities": {
    "tools": {},
    "prompts": {},
    "resources": {}
  }
}
```

**Future extensions:**

```json
{
  "capabilities": {
    "tools": {
      "caching": true,
      "filtering": true
    },
    "prompts": {
      "templates": 8
    },
    "resources": {
      "dynamic": true
    }
  }
}
```

### Notifications

**Server can send notifications:**

```ruby
def send_notification(method, params)
  notification = {
    jsonrpc: "2.0",
    method: method,
    params: params
  }
  $stdout.puts(notification.to_json)
  $stdout.flush
end
```

**Example:**

```ruby
send_notification("notifications/tools/list_changed", {})
```

---

## Performance Considerations

### Message Parsing

**Efficient JSON parsing:**

```ruby
# Stream parsing (one message per line)
line = $stdin.gets
request = JSON.parse(line, symbolize_names: true)
```

**Benefits:**

- Low memory overhead
- Fast parsing
- Supports large responses

### Response Buffering

**Flush after each response:**

```ruby
$stdout.puts(response.to_json)
$stdout.flush
```

**Why:**

- Prevents buffering delays
- Ensures Claude receives responses immediately
- Critical for interactive experience

### Tool Execution

**Async execution (future):**

```ruby
# Current: Synchronous
result = execute_tool(name, arguments)

# Future: Async with progress
send_notification("tool/progress", {percent: 50})
result = execute_tool(name, arguments)
```

---

## Error Handling Strategy

### Error Categories

**1. Protocol Errors:**

```ruby
PARSE_ERROR = -32700       # Invalid JSON
INVALID_REQUEST = -32600   # Malformed request
METHOD_NOT_FOUND = -32601  # Unknown method
INVALID_PARAMS = -32602    # Bad parameters
```

**2. Tool Errors:**

```ruby
# Returned in tool result with isError: true
{
  content: [{
    type: "text",
    text: "Error: Table not found"
  }],
  isError: true
}
```

**3. API Errors:**

```ruby
# HTTP errors from SmartSuite
401 Unauthorized → "Invalid API credentials"
404 Not Found → "Table/record not found"
429 Too Many Requests → "Rate limit exceeded"
500 Server Error → "SmartSuite API error"
```

### Error Response Format

**Protocol error:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found: invalid/method"
  }
}
```

**Tool error:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Error: Invalid table ID"
      }
    ],
    "isError": true
  }
}
```

---

## Testing Strategy

### Protocol Compliance

**Test JSON-RPC format:**

```ruby
def test_valid_request
  request = {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {}
  }

  response = handle_request(request)
  assert_equal "2.0", response[:jsonrpc]
  assert_equal 1, response[:id]
  assert response[:result]
end
```

### Tool Execution

**Test tool calls:**

```ruby
def test_list_solutions
  stub_api_request do
    result = handle_tools_call("list_solutions", {})
    assert result[:content]
    assert_equal false, result[:isError]
  end
end
```

### Error Handling

**Test error responses:**

```ruby
def test_invalid_method
  request = {
    jsonrpc: "2.0",
    id: 1,
    method: "invalid/method",
    params: {}
  }

  response = handle_request(request)
  assert response[:error]
  assert_equal -32601, response[:error][:code]
end
```

---

## MCP vs Other Protocols

### MCP vs REST API

**MCP:**

- ✅ Bidirectional (stdin/stdout)
- ✅ Tool discovery
- ✅ Prompt templates
- ✅ Native AI integration
- ❌ Requires persistent process

**REST:**

- ✅ Stateless
- ✅ Standard HTTP
- ✅ Wide tool support
- ❌ No tool discovery
- ❌ Client must know API

### MCP vs GraphQL

**MCP:**

- ✅ Tool-oriented
- ✅ AI-native design
- ✅ Prompts for guidance
- ❌ Less flexible queries

**GraphQL:**

- ✅ Flexible queries
- ✅ Schema introspection
- ✅ Wide adoption
- ❌ Not AI-optimized

---

## Future Enhancements

### Planned Features

1. **Streaming Responses**

   - Large result sets
   - Progress notifications
   - Partial results

2. **Batch Operations**

   - Multiple tool calls in one request
   - Transactional semantics
   - Rollback on error

3. **Resource Support**

   - Dynamic resources
   - Table schemas as resources
   - Cached data as resources

4. **Enhanced Prompts**

   - More templates
   - Custom prompts
   - Prompt composition

5. **Capability Negotiation**
   - Feature detection
   - Version compatibility
   - Optional features

---

## Related Documentation

- **[Architecture Overview](overview.md)** - System architecture
- **[Caching System](caching-system.md)** - Cache implementation
- **[Data Flow](data-flow.md)** - Data flow diagrams
- **[User Guide](../guides/user-guide.md)** - User-facing documentation

---

## External Resources

- [MCP Specification](https://modelcontextprotocol.io/specification)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [Claude Desktop MCP Guide](https://docs.anthropic.com/claude/docs/mcp)

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
