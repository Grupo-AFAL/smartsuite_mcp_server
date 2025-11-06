# SmartSuite MCP Server

A Model Context Protocol (MCP) server for SmartSuite, enabling AI assistants to interact with your SmartSuite workspace.

## Features

This MCP server provides the following tools organized by module:

### Workspace Operations
- **list_solutions** - List all solutions in your workspace (high-level view)
  - Optional: `include_activity_data: true` to get usage metrics for each solution
- **analyze_solution_usage** - Identify inactive or underutilized solutions based on last access date, record count, and automation activity

### Table Operations
- **list_tables** - List all tables in your SmartSuite workspace
- **get_table** - Get a specific table's structure (fields, slugs, types) - **Use this first to understand what fields are available**
- **create_table** - Create a new table (application) in a solution

### Record Operations
- **list_records** - Query records from a table with pagination support
- **get_record** - Retrieve a specific record by ID
- **create_record** - Create new records in tables
- **update_record** - Update existing records
- **delete_record** - Delete a record from a table

### Field Operations
- **add_field** - Add a new field to a table
- **bulk_add_fields** - Add multiple fields to a table in one request
- **update_field** - Update an existing field's properties
- **delete_field** - Delete a field from a table

### Member Operations
- **list_members** - List all members (users) in your workspace - **Use this to get user IDs for assigning people to records**
- **list_teams** - List all teams in your workspace
- **get_team** - Get a specific team by ID with member details

### Comment Operations
- **list_comments** - List all comments for a specific record with message content, author, and timestamps
- **add_comment** - Add a comment to a record with optional user assignment (plain text automatically formatted to rich text)

### View Operations
- **get_view_records** - Get records for a specific view (report) with the view's filters and configuration applied
- **create_view** - Create a new view (report) in a table with custom filters, sorting, and display settings

### API Usage Tracking
- **get_api_stats** - View detailed API usage statistics by user, solution, table, method, and endpoint
- **reset_api_stats** - Reset API usage statistics

All API calls are automatically tracked and persisted across sessions, helping you monitor usage and stay within SmartSuite's rate limits.

### MCP Prompts (Filter Examples)
This server provides ready-to-use prompts that show AI assistants exactly how to construct filters:

- **filter_active_records** - Filter records where status is "active" (or any custom status field)
- **filter_by_date_range** - Filter records within a date range
- **list_tables_by_solution** - List tables filtered by solution ID
- **filter_records_contains_text** - Filter records where a field contains specific text

These prompts provide concrete JSON examples that make it much easier for AI assistants to construct valid filters without guessing the syntax.

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
  "solutions": [
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
  ],
  "count": 2
}
```

### list_members

Lists all members (users) in your SmartSuite workspace. **Use this tool to get user IDs when you need to assign people to records.**

**Token Optimization:** Use the `solution_id` parameter to filter members server-side, returning only those with access to a specific solution. This significantly reduces token usage.

**Parameters:**
- `limit` (optional): Maximum number of members to return (default: 100). Ignored when solution_id is provided.
- `offset` (optional): Number of members to skip (for pagination). Ignored when solution_id is provided.
- `solution_id` (optional): Filter members by solution ID. Returns only members who have access to this solution. **Recommended for token savings.**

**Example (all members):**
```json
{
  "limit": 100,
  "offset": 0
}
```

**Example (filtered by solution - RECOMMENDED):**
```json
{
  "solution_id": "sol_abc123"
}
```

**Example response (all members):**
```json
{
  "members": [
    {
      "id": "usr_abc123",
      "title": "John Doe",
      "email": "john@example.com",
      "first_name": "John",
      "last_name": "Doe",
      "role": "admin",
      "status": "active"
    },
    {
      "id": "usr_def456",
      "title": "Jane Smith",
      "email": "jane@example.com",
      "first_name": "Jane",
      "last_name": "Smith",
      "role": "member",
      "status": "active"
    }
  ],
  "count": 2,
  "total_count": 2
}
```

**Example response (filtered by solution):**
```json
{
  "members": [
    {
      "id": "usr_abc123",
      "title": "John Doe",
      "email": "john@example.com",
      "role": "admin",
      "status": "active"
    }
  ],
  "count": 1,
  "total_count": 1,
  "filtered_by_solution": "sol_abc123"
}
```

**Use case - Assigning users to records:**

When creating or updating records with user assignment fields, use the user `id` from this response:

```json
{
  "table_id": "tbl_projects",
  "data": {
    "title": "New Project",
    "assigned_to": "usr_abc123"
  }
}
```

**Workflow recommendation:**
1. If working within a specific solution, use `list_members` with `solution_id` to get only relevant members (saves tokens)
2. If you need all workspace members, call `list_members` without parameters

### list_teams

Lists all teams in your SmartSuite workspace. Teams are groups of users that can be assigned permissions to solutions and tables.

**Parameters:** None

**Example:**
```json
{}
```

**Example response:**
```json
[
  {
    "id": "team_abc123",
    "name": "Engineering Team",
    "member_count": 15,
    "created": "2024-01-15T10:30:00Z"
  },
  {
    "id": "team_def456",
    "name": "Marketing Team",
    "member_count": 8,
    "created": "2024-02-20T14:45:00Z"
  }
]
```

### get_team

Retrieves a specific team by ID including its members and details.

**Parameters:**
- `team_id` (required): The ID of the team to retrieve

**Example:**
```json
{
  "team_id": "team_abc123"
}
```

**Example response:**
```json
{
  "id": "team_abc123",
  "name": "Engineering Team",
  "members": [
    {
      "id": "usr_123",
      "name": "John Doe",
      "email": "john@example.com"
    },
    {
      "id": "usr_456",
      "name": "Jane Smith",
      "email": "jane@example.com"
    }
  ],
  "created": "2024-01-15T10:30:00Z",
  "updated": "2024-03-10T16:20:00Z"
}
```

**Use case:**
Teams can be used when configuring permissions for solutions or when you need to understand team structures in your workspace.

### list_tables

Lists all tables (applications) in your workspace. Optionally filter by solution_id to only show tables from a specific solution.

**Parameters:**
- `solution_id` (optional): Filter tables by solution ID. Use `list_solutions` first to get solution IDs.

**Example (all tables):**
```json
{
  "table_id": ""
}
```

**Example (filtered by solution):**
```json
{
  "solution_id": "sol_abc123"
}
```

**Example response:**
```json
{
  "tables": [
    {
      "id": "table_id",
      "name": "Customers",
      "solution_id": "sol_abc123"
    }
  ],
  "count": 1
}
```

### get_table

**IMPORTANT: Use this tool FIRST before querying records.** Get a specific table by ID including its structure (fields, field slugs, field types). This tells you what fields are available for filtering and selection.

**⚡ OPTIMIZED FOR MINIMAL CONTEXT USAGE:**
- **83.8% smaller** - Structure data is filtered to only essential information
- **Typical savings**: ~19,000 tokens per table (from ~22,663 to ~3,666 tokens for a 36-field table)
- **What's included**: Only the fields needed for fetching, filtering, sorting, creating, and updating records
- **What's removed**: UI configuration, help text, display settings, and other metadata not needed for data operations

**Parameters:**
- `table_id` (required): The ID of the table

**Example:**
```json
{
  "table_id": "tbl_abc123"
}
```

**Example response (minimal structure):**
```json
{
  "id": "tbl_abc123",
  "name": "Customers",
  "solution_id": "sol_xyz",
  "structure": [
    {
      "slug": "title",
      "label": "Title",
      "field_type": "recordtitlefield",
      "params": {
        "primary": true,
        "required": true,
        "unique": true
      }
    },
    {
      "slug": "status",
      "label": "Status",
      "field_type": "statusfield",
      "params": {
        "required": false,
        "unique": false,
        "choices": [
          {"label": "Active", "value": "active"},
          {"label": "Inactive", "value": "inactive"}
        ]
      }
    },
    {
      "slug": "company",
      "label": "Company",
      "field_type": "linkedrecordfield",
      "params": {
        "required": true,
        "unique": false,
        "linked_application": "tbl_companies",
        "entries_allowed": "single"
      }
    }
  ]
}
```

**What's included in params:**
- `primary` - If the field is the primary field (only if true)
- `required` - Whether the field is required (always included)
- `unique` - Whether the field must be unique (always included)
- `choices` - For choice/status fields, **only label and value** (colors, icons, etc. removed)
- `linked_application` - For linked record fields, the target table ID
- `entries_allowed` - For linked records, whether it's "single" or "multiple"

**What's removed (saves 83.8% context):**
- UI display settings (`display_format`, `column_widths`, `visible_fields`, etc.)
- Help text and documentation (`help_doc`, `help_text_display_format`)
- Default values and placeholders
- Width, system flags, validation states
- For choices: colors, icons, ordering, help text, completion status
- For linked records: filter data, sort data, modal configuration

**Workflow recommendation:**
1. Use `get_table` to see available fields and their slugs
2. Use the field slugs in `list_records` filters and fields parameters
3. This prevents errors from using wrong field names

### create_table

Creates a new table (application) in a SmartSuite solution.

**Parameters:**
- `solution_id` (required): The ID of the solution where the table will be created
- `name` (required): Name of the new table
- `description` (optional): Description for the table
- `structure` (optional): Array of field definitions for the table. If not provided, an empty array will be used.

**Example (basic table):**
```json
{
  "solution_id": "sol_abc123",
  "name": "Customers",
  "description": "Customer relationship management"
}
```

**Example (table with initial fields):**
```json
{
  "solution_id": "sol_abc123",
  "name": "Customers",
  "description": "Customer relationship management",
  "structure": [
    {
      "slug": "s7e8c12e98",
      "label": "Company",
      "field_type": "textfield"
    },
    {
      "slug": "s7e8c12e99",
      "label": "Email",
      "field_type": "emailfield"
    }
  ]
}
```

**Example response:**
```json
{
  "id": "tbl_xyz789",
  "name": "Customers",
  "solution_id": "sol_abc123",
  "description": "Customer relationship management",
  "structure": [...],
  "created": "2025-11-05T12:00:00Z"
}
```

**Note:**
- If you don't provide a `structure`, the table will be created with an empty field structure
- You can add fields after creation using `add_field` or `bulk_add_fields`
- Field slugs should be unique alphanumeric identifiers (typically 10 characters)

### list_records

Lists records from a specific table with optional filtering and sorting.

**⚡ ULTRA-MINIMAL CONTEXT USAGE:**
- **REQUIRED**: You MUST specify either `fields` parameter OR `summary_only: true`
- **Automatic limit**: Without a filter, limit is automatically capped at 2 records (prevents excessive token usage)
- **Plain text format**: Responses are returned as plain text (saves 30-50% tokens vs JSON)
- **Summary mode**: Get statistics without record data (minimal context)

**Parameters:**
- `table_id` (required): The ID of the table
- `limit` (optional): Number of records to return (default: **5**). Without a filter, automatically reduced to 2.
- `offset` (optional): Number of records to skip (for pagination)
- `filter` (optional): Filter criteria with operator and fields array
- `sort` (optional): Sort criteria as array of field-direction pairs
- `fields` (REQUIRED unless using summary_only): Array of specific field slugs to return (includes id + title automatically)
- `summary_only` (optional): Boolean. If true, returns statistics instead of records (no fields parameter needed)
- `full_content` (optional): Boolean. If true, returns full field content without truncation. Default (false) truncates strings to 500 chars. **Use this when you need complete field values** (like full descriptions) to avoid making multiple `get_record` calls.

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

**⚠️ IMPORTANT: Date Value Objects**

Date fields require a special date value object format instead of a simple string:

```json
{
  "field": "due_date",
  "comparison": "is_after",
  "value": {
    "date_mode": "exact_date",
    "date_mode_value": "2025-01-01"
  }
}
```

**Date modes:**
- `exact_date` - Specific date (YYYY-MM-DD format)
- `today` - Current date
- Other modes available (see SmartSuite API docs)

**Example: Minimal Fields (Recommended):**
```json
{
  "table_id": "abc123",
  "fields": ["status"]
}
```
Returns (plain text):
```
Found 2 records (total: 50)

Record 1:
  id: rec_123
  title: First Record
  status: active

Record 2:
  id: rec_456
  title: Second Record
  status: pending
```
Note: Without a filter, limit is automatically capped at 2 records.

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
  },
  "fields": ["status", "priority"]
}
```
Returns: Plain text with up to 20 records (filter allows higher limits)

**Example with Date Filter:**
```json
{
  "table_id": "abc123",
  "limit": 50,
  "filter": {
    "operator": "and",
    "fields": [
      {
        "field": "due_date",
        "comparison": "is_after",
        "value": {
          "date_mode": "exact_date",
          "date_mode_value": "2025-01-01"
        }
      },
      {
        "field": "due_date",
        "comparison": "is_before",
        "value": {
          "date_mode": "exact_date",
          "date_mode_value": "2025-12-31"
        }
      }
    ]
  },
  "fields": ["title", "due_date", "status"]
}
```
Returns: Plain text with records where due_date is in 2025

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
  ],
  "fields": ["status", "priority", "due_date"]
}
```
Returns: Plain text with filtered, sorted records

**Example with Summary Only (Ultra-Minimal Context):**
```json
{
  "table_id": "abc123",
  "summary_only": true
}
```
Returns:
```json
{
  "summary": "Found 5 records (total: 50)\n  status: active (3), pending (2)\n  priority: high (2), low (3)",
  "count": 5,
  "total_count": 50
}
```

**Response Optimization:**

- **Plain text format**: All responses are in plain text (saves 30-50% tokens vs JSON)
- **Field selection**: Only requested fields + id/title are returned
- **Summary mode**: Returns statistics only, no record data (minimal tokens)
- **Automatic limiting**: Without filter, maximum 2 records (prevents excessive usage)
- **Smart truncation**:
  - Default: Strings truncated to 500 chars (reasonable safety net)
  - Rich text fields: Preview kept at ~500 chars
  - Arrays: First 10 items
  - With `full_content: true`: No truncation - get complete field values

**When to use `full_content: true`:**
- When you need complete descriptions, long text fields, or full rich text content
- Prevents needing multiple `get_record` calls for individual records
- Example: Getting full descriptions from filtered records

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

### delete_record

Deletes a record from a table.

**Parameters:**
- `table_id` (required): The ID of the table
- `record_id` (required): The ID of the record to delete

**Example:**
```json
{
  "table_id": "abc123",
  "record_id": "rec456"
}
```

**Example response:**
```json
{
  "message": "Record deleted successfully"
}
```

**Note:** This operation is permanent and cannot be undone. Ensure you have the correct record_id before deleting.

## Field Management Operations

### add_field

Adds a new field to a SmartSuite table.

**Parameters:**
- `table_id` (required): The ID of the table to add the field to
- `field_data` (required): Field configuration object with slug, label, field_type, and params
- `field_position` (optional): Position metadata to place field after another field
- `auto_fill_structure_layout` (optional): Enable automatic layout structure updates (default: true)

**Example (basic text field):**
```json
{
  "table_id": "tbl_abc123",
  "field_data": {
    "slug": "my_field_01",
    "label": "My Custom Field",
    "field_type": "textfield",
    "params": {
      "help_doc": {
        "data": {
          "type": "doc",
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "Enter text here"
                }
              ]
            }
          ]
        },
        "html": "<p>Enter text here</p>",
        "preview": "Enter text here"
      },
      "help_text_display_format": "inline"
    },
    "is_new": true
  }
}
```

**Field types available:** textfield, numberfield, datefield, statusfield, singleselectfield, multiselectfield, userfield, linkedrecordfield, and many more.

**Note:** The `slug` should be a unique alphanumeric identifier (typically 10 characters). The `help_doc` parameter uses rich text format similar to SmartDoc.

### bulk_add_fields

Adds multiple fields to a table in one request for better performance.

**Parameters:**
- `table_id` (required): The ID of the table to add fields to
- `fields` (required): Array of field configuration objects
- `set_as_visible_fields_in_reports` (optional): Array of view IDs where the added fields should be visible

**Example:**
```json
{
  "table_id": "tbl_abc123",
  "fields": [
    {
      "slug": "field_01",
      "label": "Field One",
      "field_type": "textfield",
      "params": {},
      "is_new": true
    },
    {
      "slug": "field_02",
      "label": "Field Two",
      "field_type": "numberfield",
      "params": {},
      "is_new": true
    }
  ]
}
```

**Note:** Certain field types are not supported in bulk operations (e.g., Formula, Count, TimeTracking). Use `add_field` for these types.

### update_field

Updates an existing field's properties in a table.

**Parameters:**
- `table_id` (required): The ID of the table containing the field
- `slug` (required): The slug of the field to update
- `field_data` (required): Updated field configuration object

**Example (updating field label and help text):**
```json
{
  "table_id": "tbl_abc123",
  "slug": "my_field_01",
  "field_data": {
    "label": "Updated Field Name",
    "field_type": "textfield",
    "params": {
      "help_doc": {
        "data": {
          "type": "doc",
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "New help text"
                }
              ]
            }
          ]
        },
        "html": "<p>New help text</p>",
        "preview": "New help text"
      },
      "help_text_display_format": "tooltip"
    }
  }
}
```

**Note:** The slug in `field_data` will be automatically added from the `slug` parameter.

### delete_field

Deletes a field from a table.

**Parameters:**
- `table_id` (required): The ID of the table containing the field
- `slug` (required): The slug of the field to delete

**Example:**
```json
{
  "table_id": "tbl_abc123",
  "slug": "my_field_01"
}
```

**Example response:**
Returns the deleted field object.

**Note:** This operation is permanent and cannot be undone. All data in this field will be lost.

## Comment Operations

### list_comments

Lists all comments for a specific record. Returns an array of comment objects with message content, author information, timestamps, and assignment details.

**Parameters:**
- `record_id` (required): The ID of the record whose comments to retrieve

**Example:**
```json
{
  "record_id": "rec_abc123"
}
```

**Example response:**
```json
{
  "count": null,
  "results": [
    {
      "id": "comment_123",
      "message": {
        "data": {
          "type": "doc",
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "This is a comment"
                }
              ]
            }
          ]
        },
        "html": "<p>This is a comment</p>",
        "preview": "This is a comment"
      },
      "record": "rec_abc123",
      "application": "tbl_def456",
      "solution": "sol_xyz789",
      "member": "usr_author123",
      "created_on": "2025-01-15T10:30:00Z",
      "assigned_to": null,
      "followers": ["usr_author123"],
      "reactions": [],
      "key": 1
    }
  ]
}
```

**Comment Object Fields:**
- `id`: Unique comment identifier
- `message`: Rich text message with data, html, and preview
- `record`: Record ID the comment belongs to
- `application`: Table/app ID
- `solution`: Solution ID
- `member`: User ID of comment creator
- `created_on`: Creation timestamp
- `assigned_to`: Optional assigned user ID
- `followers`: Array of user IDs following the comment
- `reactions`: Array of emoji reactions
- `key`: Comment number on the record (1-indexed)

### add_comment

Creates a new comment on a record. Supports plain text input which is automatically formatted to SmartSuite's rich text format.

**Parameters:**
- `table_id` (required): The ID of the table/application containing the record
- `record_id` (required): The ID of the record to add the comment to
- `message` (required): The comment text (plain text - will be automatically formatted)
- `assigned_to` (optional): User ID to assign the comment to (use `list_members` to get user IDs)

**Example (simple comment):**
```json
{
  "table_id": "tbl_abc123",
  "record_id": "rec_def456",
  "message": "This task is ready for review"
}
```

**Example (with assignment):**
```json
{
  "table_id": "tbl_abc123",
  "record_id": "rec_def456",
  "message": "Please review this ASAP",
  "assigned_to": "usr_xyz789"
}
```

**Example response:**
```json
{
  "id": "comment_new123",
  "message": {
    "data": {
      "type": "doc",
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "This task is ready for review"
            }
          ]
        }
      ]
    },
    "html": "<p>This task is ready for review</p>",
    "preview": "This task is ready for review"
  },
  "record": "rec_def456",
  "application": "tbl_abc123",
  "member": "usr_current_user",
  "created_on": "2025-01-15T14:30:00Z",
  "assigned_to": null,
  "followers": ["usr_current_user"],
  "key": 4
}
```

**Message Formatting:**
The server automatically converts plain text to SmartSuite's rich text format (TipTap/ProseMirror). You just provide a simple string, and it's formatted as:
```ruby
# Input
"This is a comment"

# Automatically becomes
{
  "data": {
    "type": "doc",
    "content": [
      {
        "type": "paragraph",
        "content": [
          {"type": "text", "text": "This is a comment"}
        ]
      }
    ]
  }
}
```

**Workflow Example:**
1. Use `list_members` to get user IDs if you need to assign the comment
2. Call `add_comment` with plain text message
3. Comment appears in SmartSuite with proper formatting

### get_view_records

Gets records for a specific view (report) with the view's configured filters, sorting, and field visibility applied.

In SmartSuite, views (also called "reports") are saved configurations that define how data is displayed, filtered, and organized. This tool retrieves records matching a view's configuration.

**Parameters:**
- `table_id` (required): The table identifier
- `view_id` (required): The view/report identifier
- `with_empty_values` (optional): Whether to include empty field values (default: false)

**Example:**
```json
{
  "table_id": "tbl_abc123",
  "view_id": "view_def456",
  "with_empty_values": false
}
```

**Example response:**
```json
{
  "records": [
    {
      "id": "rec_123",
      "title": "Active Project",
      "status": "In Progress",
      "due_date": "2025-02-01"
    }
  ],
  "view_config": {
    "id": "view_def456",
    "label": "Active Projects",
    "filters": {...}
  }
}
```

### create_view

Creates a new view (report) in a table with specified configuration.

Views can be of different types (grid, kanban, calendar, etc.) and include filters, sorting, grouping, and display settings.

**Parameters:**
- `application` (required): Table identifier where view is created
- `solution` (required): Solution identifier containing the table
- `label` (required): Display name of the view
- `view_mode` (required): View type - one of: `grid`, `map`, `calendar`, `kanban`, `gallery`, `timeline`, `gantt`
- `description` (optional): View description
- `autosave` (optional): Enable autosave (default: true)
- `is_locked` (optional): Lock the view (default: false)
- `is_private` (optional): Make view private (default: false)
- `is_password_protected` (optional): Password protect view (default: false)
- `order` (optional): Display position in view list
- `state` (optional): View state configuration (filters, fields, sort, grouping)
- `map_state` (optional): Map configuration for map views
- `sharing` (optional): Sharing settings

**Example (simple grid view):**
```json
{
  "application": "tbl_abc123",
  "solution": "sol_def456",
  "label": "Active Tasks",
  "view_mode": "grid"
}
```

**Example (kanban view with configuration):**
```json
{
  "application": "tbl_abc123",
  "solution": "sol_def456",
  "label": "Project Board",
  "view_mode": "kanban",
  "description": "Kanban board for project tracking",
  "state": {
    "filter": {
      "operator": "and",
      "fields": [
        {"field": "status", "comparison": "is_not", "value": "Completed"}
      ]
    },
    "sort": [
      {"field": "priority", "direction": "desc"}
    ],
    "group_by": "status"
  }
}
```

**Example response:**
```json
{
  "id": "view_xyz789",
  "label": "Active Tasks",
  "view_mode": "grid",
  "application": "tbl_abc123",
  "solution": "sol_def456",
  "autosave": true,
  "is_locked": false,
  "is_private": false
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
    "PATCH": 25,
    "DELETE": 5
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
- **By HTTP Method**: GET, POST, PATCH, DELETE
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
