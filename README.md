# SmartSuite MCP Server

A Model Context Protocol (MCP) server for SmartSuite, enabling AI assistants to interact with your SmartSuite workspace.

## Features

This MCP server provides the following tools:

### Data Operations
- **list_solutions** - List all solutions in your workspace (high-level view)
- **list_tables** - List all tables in your SmartSuite workspace
- **list_records** - Query records from a table with pagination support
- **get_record** - Retrieve a specific record by ID
- **create_record** - Create new records in tables
- **update_record** - Update existing records

### API Usage Tracking
- **get_api_stats** - View detailed API usage statistics by user, solution, table, method, and endpoint
- **reset_api_stats** - Reset API usage statistics

All API calls are automatically tracked and persisted across sessions, helping you monitor usage and stay within SmartSuite's rate limits.

## Prerequisites

- Ruby 3.0 or higher
- SmartSuite account with API access
- SmartSuite API key and Account ID

## Setup

### 1. Get SmartSuite API Credentials

1. Log in to your SmartSuite workspace
2. Go to Settings > API
3. Generate an API key
4. Note your Account ID (Workspace ID)

### 2. Configure Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` and add your credentials:

```bash
SMARTSUITE_API_KEY=your_api_key_here
SMARTSUITE_ACCOUNT_ID=your_account_id_here
```

### 3. Make the Server Executable

```bash
chmod +x smartsuite_server.rb
```

## Usage with Claude Desktop

Add this configuration to your Claude Desktop config file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["/absolute/path/to/smartsuite_mcp/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "your_api_key_here",
        "SMARTSUITE_ACCOUNT_ID": "your_account_id_here"
      }
    }
  }
}
```

Replace `/absolute/path/to/smartsuite_mcp/` with the actual path to this directory.

## Testing

You can test the server manually using stdio:

```bash
export SMARTSUITE_API_KEY=your_api_key
export SMARTSUITE_ACCOUNT_ID=your_account_id
ruby smartsuite_server.rb
```

Then send MCP protocol messages via stdin. For example:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

## Available Tools

### list_solutions

Lists all solutions in your SmartSuite workspace. Solutions are high-level containers that group related tables together.

**Example response:**
```json
{
  "items": [
    {
      "id": "sol_abc123",
      "name": "Customer Management",
      "logo_icon": "users",
      "logo_color": "#3B82F6"
    },
    {
      "id": "sol_def456",
      "name": "Project Tracking",
      "logo_icon": "folder",
      "logo_color": "#10B981"
    }
  ]
}
```

### list_tables

Lists all tables (applications) in your workspace. This can return a large result if you have many tables - consider using `list_solutions` first to see the high-level organization.

**Example response:**
```json
{
  "items": [
    {
      "id": "table_id",
      "name": "Customers",
      "structure": [...]
    }
  ]
}
```

### list_records

Lists records from a specific table with optional filtering and sorting.

**⚡ Response Optimization:** This tool automatically filters verbose fields (description, comments_count, ranking, etc.) and truncates long text to reduce context usage. Use the `fields` parameter to specify exactly which fields you need.

**Parameters:**
- `table_id` (required): The ID of the table
- `limit` (optional): Number of records to return (default: 50)
- `offset` (optional): Number of records to skip (for pagination)
- `filter` (optional): Filter criteria with operator and fields array
- `sort` (optional): Sort criteria as array of field-direction pairs
- `fields` (optional): Array of specific field slugs to return. If not provided, returns essential fields (id, title, first_created, last_updated) plus custom fields, with verbose metadata stripped

**Filter Structure:**

The filter parameter uses the following structure:
```json
{
  "operator": "and",  // or "or" - combines multiple conditions
  "fields": [
    {
      "field": "field_slug",      // Field identifier
      "comparison": "is",          // Comparison operator
      "value": "value"             // Value to compare against
    }
  ]
}
```

**Available Comparison Operators:**
- `is` / `is_not` - Exact match / not equal
- `contains` / `does_not_contain` - Text contains / doesn't contain
- `is_equal_to` / `is_greater_than` / `is_less_than` - Numeric comparisons
- `is_any_of` / `is_none_of` - Multiple value matching
- `is_empty` / `is_not_empty` - Empty/non-empty check
- `is_before` / `is_after` / `is_on` - Date comparisons

**Basic Example:**
```json
{
  "table_id": "abc123",
  "limit": 10,
  "offset": 0
}
```

**Example with Filter:**
```json
{
  "table_id": "abc123",
  "limit": 20,
  "filter": {
    "operator": "and",
    "fields": [
      {
        "field": "status",
        "comparison": "is",
        "value": "active"
      }
    ]
  }
}
```

**Example with Sort:**
```json
{
  "table_id": "abc123",
  "limit": 50,
  "sort": [
    {"field": "created_on", "direction": "desc"},
    {"field": "title", "direction": "asc"}
  ]
}
```

**Example with Filter and Sort:**
```json
{
  "table_id": "abc123",
  "limit": 100,
  "offset": 0,
  "filter": {
    "operator": "and",
    "fields": [
      {
        "field": "status",
        "comparison": "is",
        "value": "active"
      },
      {
        "field": "priority",
        "comparison": "is_greater_than",
        "value": 3
      }
    ]
  },
  "sort": [
    {"field": "priority", "direction": "desc"},
    {"field": "due_date", "direction": "asc"}
  ]
}
```

**Example with Specific Fields (Reduces Response Size):**
```json
{
  "table_id": "abc123",
  "limit": 50,
  "fields": ["status", "priority", "assigned_to", "due_date"]
}
```

**Response Filtering Behavior:**

By default (without `fields` parameter):
- ✅ Keeps: `id`, `title`, `first_created`, `last_updated`, all custom fields
- ❌ Removes: `description`, `comments_count`, `ranking`, `application_slug`, `deleted_date`
- ✂️ Truncates: Strings > 500 chars, Arrays > 10 items, Rich text fields

With `fields` parameter:
- ✅ Returns only specified fields plus essential metadata (`id`, `title`, etc.)
- ✂️ Still applies truncation to prevent context overflow

### get_record

Retrieves a specific record by ID.

**Parameters:**
- `table_id` (required): The ID of the table
- `record_id` (required): The ID of the record

### create_record

Creates a new record in a table.

**Parameters:**
- `table_id` (required): The ID of the table
- `data` (required): Object with field slugs as keys and values

**Example:**
```json
{
  "table_id": "abc123",
  "data": {
    "title": "New Customer",
    "status": "active",
    "email": "customer@example.com"
  }
}
```

### update_record

Updates an existing record.

**Parameters:**
- `table_id` (required): The ID of the table
- `record_id` (required): The ID of the record to update
- `data` (required): Object with field slugs and new values

**Example:**
```json
{
  "table_id": "abc123",
  "record_id": "rec456",
  "data": {
    "status": "completed"
  }
}
```

### get_api_stats

Retrieves comprehensive API call statistics.

Tracks API usage across multiple dimensions:
- Total calls and timestamps
- Calls by user (API key hashed for privacy)
- Calls by HTTP method (GET, POST, PATCH)
- Calls by SmartSuite solution
- Calls by table (application)
- Calls by endpoint

**Example response:**
```json
{
  "summary": {
    "total_calls": 150,
    "first_call": "2025-01-15T10:30:00Z",
    "last_call": "2025-01-15T14:45:00Z",
    "unique_users": 1,
    "unique_solutions": 2,
    "unique_tables": 5
  },
  "by_user": {
    "a1b2c3d4": 150
  },
  "by_method": {
    "GET": 50,
    "POST": 75,
    "PATCH": 25
  },
  "by_solution": {
    "sol_abc123": 100,
    "sol_def456": 50
  },
  "by_table": {
    "tbl_customers": 80,
    "tbl_orders": 70
  },
  "by_endpoint": {
    "/applications/": 10,
    "/applications/tbl_customers/records/list/": 40
  }
}
```

**Note:** Statistics are persisted to `~/.smartsuite_mcp_stats.json` and survive server restarts.

### reset_api_stats

Resets all API call statistics back to zero.

**Example response:**
```json
{
  "status": "success",
  "message": "API statistics have been reset"
}
```

## API Call Tracking

This server automatically tracks all API calls made to SmartSuite. The tracking includes:

- **By User**: API key is hashed (SHA256, first 8 chars) for privacy
- **By Solution**: Extracted from endpoints like `/solutions/{id}/`
- **By Table**: Extracted from endpoints like `/applications/{id}/`
- **By HTTP Method**: GET, POST, PATCH
- **By Endpoint**: Full endpoint path
- **Timestamps**: First and last API call times

Statistics are automatically saved to `~/.smartsuite_mcp_stats.json` after each API call and persist across server restarts.

Use the `get_api_stats` tool to view current statistics or `reset_api_stats` to clear them.

## API Rate Limits

SmartSuite enforces these rate limits:
- Standard: 5 requests per second per user
- Overage: 2 requests per second when exceeding monthly allowance
- Hard limit: Requests exceeding 125% of monthly limits are denied

## Development & Testing

### Running Tests

This project includes a comprehensive test suite using Minitest (part of Ruby's standard library).

**Install dependencies:**
```bash
bundle install
```

**Run all tests:**
```bash
bundle exec rake test
# or
ruby test/test_smartsuite_server.rb
```

**Run with verbose output:**
```bash
bundle exec rake test TESTOPTS="-v"
```

### Test Coverage

The test suite includes:
- **MCP Protocol Tests** - Initialize, tools/list, prompts/list, resources/list
- **Tool Handler Tests** - All SmartSuite tools (list_solutions, list_tables, etc.)
- **API Tracking Tests** - Statistics tracking, reset functionality
- **Data Formatting Tests** - Response filtering and size optimization
- **Error Handling Tests** - Unknown methods, missing parameters

### Adding New Tests

Tests are located in `test/test_smartsuite_server.rb`. To add a new test:

1. Create a new test method starting with `test_`
2. Use Minitest assertions: `assert_equal`, `assert_includes`, `assert_raises`, etc.
3. Run the tests to ensure they pass

**Example:**
```ruby
def test_my_new_feature
  result = call_private_method(:my_method)
  assert_equal 'expected', result
end
```

## Troubleshooting

### Environment Variables Not Set

If you see "SMARTSUITE_API_KEY environment variable is required", ensure you've set the environment variables either:
- In the Claude Desktop config file
- In your shell environment when testing manually

### API Request Failed

Check that:
- Your API key is valid and not expired
- Your Account ID is correct
- The table IDs you're using exist in your workspace
- You haven't exceeded rate limits

## Resources

- [SmartSuite API Documentation](https://developers.smartsuite.com/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Claude Desktop](https://claude.ai/download)

## License

MIT
