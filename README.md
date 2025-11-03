# SmartSuite MCP Server

A Model Context Protocol (MCP) server for SmartSuite, enabling AI assistants to interact with your SmartSuite workspace.

## Features

This MCP server provides the following tools:

- **list_tables** - List all tables in your SmartSuite workspace
- **list_records** - Query records from a table with pagination support
- **get_record** - Retrieve a specific record by ID
- **create_record** - Create new records in tables
- **update_record** - Update existing records

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

### list_tables

Lists all tables in your workspace.

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

Lists records from a specific table.

**Parameters:**
- `table_id` (required): The ID of the table
- `limit` (optional): Number of records to return (default: 50)
- `offset` (optional): Number of records to skip

**Example:**
```json
{
  "table_id": "abc123",
  "limit": 10,
  "offset": 0
}
```

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

## API Rate Limits

SmartSuite enforces these rate limits:
- Standard: 5 requests per second per user
- Overage: 2 requests per second when exceeding monthly allowance
- Hard limit: Requests exceeding 125% of monthly limits are denied

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
