# API Reference

Complete reference documentation for all SmartSuite MCP Server operations.

## Overview

The SmartSuite MCP Server provides full programmatic access to your SmartSuite workspace through 26 tools organized into 8 modules. Each module handles a specific aspect of SmartSuite operations.

## Quick Navigation

| Module | Operations | Description |
|--------|------------|-------------|
| **[Workspace](workspace.md)** | 4 tools | Solutions, usage analysis, ownership |
| **[Tables](tables.md)** | 3 tools | Table/application management |
| **[Records](records.md)** | 5 tools | Data CRUD operations |
| **[Fields](fields.md)** | 4 tools | Schema management |
| **[Members](members.md)** | 4 tools | Users and teams |
| **[Comments](comments.md)** | 2 tools | Collaboration |
| **[Views](views.md)** | 2 tools | Saved configurations |
| **[Stats](stats.md)** | 2 tools | API usage tracking |

---

## Module Details

### [Workspace Operations](workspace.md)

Manage solutions (workspaces) and analyze usage patterns.

**Tools:**
- `list_solutions` - List all accessible solutions
- `list_solutions_by_owner` - Filter solutions by owner
- `analyze_solution_usage` - Identify inactive workspaces
- `get_solution_most_recent_record_update` - Check data activity

**Common use cases:**
- Find your workspaces
- Identify unused solutions for cleanup
- Audit solution ownership
- Verify data activity

**Read more:** [Workspace Operations →](workspace.md)

---

### [Table Operations](tables.md)

Create and manage tables (applications) within solutions.

**Tools:**
- `list_tables` - List all tables or filter by solution
- `get_table` - Get table structure and field definitions
- `create_table` - Create new table with custom fields

**Common use cases:**
- Discover available tables
- Understand table structure before queries
- Create tables programmatically
- Get field slugs for operations

**Read more:** [Table Operations →](tables.md)

---

### [Record Operations](records.md)

Core data operations with intelligent caching.

**Tools:**
- `list_records` - Query records with filtering (cache-first)
- `get_record` - Fetch single record by ID
- `create_record` - Create new records
- `update_record` - Update existing records
- `delete_record` - Delete records permanently

**Common use cases:**
- Query and filter data
- Create/update/delete records
- Bulk data operations
- Cache-optimized querying

**Key features:**
- Cache-first strategy (4-hour TTL)
- Local SQL filtering on cached data
- Plain text responses (60%+ token savings)
- Required field selection
- Pagination support

**Read more:** [Record Operations →](records.md)

---

### [Field Operations](fields.md)

Manage table schemas and field configurations.

**Tools:**
- `add_field` - Add single field to table
- `bulk_add_fields` - Add multiple fields at once
- `update_field` - Update field configuration
- `delete_field` - Remove field permanently

**Common use cases:**
- Add custom fields to tables
- Update select field choices
- Modify field requirements
- Bulk field initialization

**Field types supported:**
- Text fields (text, textarea, email, phone, etc.)
- Numeric fields (number, currency, rating, etc.)
- Select fields (single, multiple)
- Date fields (date, due date, date range)
- Linked records
- User assignment fields
- Yes/No (boolean)
- And many more...

**Read more:** [Field Operations →](fields.md)

---

### [Member Operations](members.md)

Access user and team information.

**Tools:**
- `list_members` - List all workspace members
- `search_member` - Search by name or email
- `list_teams` - List all teams
- `get_team` - Get team details with members

**Common use cases:**
- Find user IDs for filtering
- Search for users by email
- Get team member lists
- Audit workspace access

**Read more:** [Member Operations →](members.md)

---

### [Comment Operations](comments.md)

Collaboration through record comments.

**Tools:**
- `list_comments` - Get all comments on a record
- `add_comment` - Add new comment with assignment

**Common use cases:**
- View comment threads
- Add status updates
- Request actions with assignments
- Track collaboration

**Features:**
- Plain text input (auto-formatted)
- User assignments with notifications
- Multi-line support
- Followers and reactions tracking

**Read more:** [Comment Operations →](comments.md)

---

### [View Operations](views.md)

Work with saved view configurations.

**Tools:**
- `get_view_records` - Fetch records with view's filters applied
- `create_view` - Create new saved views

**Common use cases:**
- Use existing view configurations
- Create programmatic views
- Consistent data display
- Department-specific views

**View types:**
- Grid (table)
- Calendar (date-based)
- Kanban (board)
- Map (geographic)
- Gallery (cards)
- Timeline (Gantt)
- Chart (visualization)

**Read more:** [View Operations →](views.md)

---

### [API Statistics](stats.md)

Monitor and analyze API usage.

**Tools:**
- `get_api_stats` - View detailed usage statistics
- `reset_api_stats` - Clear statistics and start fresh

**Common use cases:**
- Monitor API call counts
- Stay within rate limits
- Identify performance bottlenecks
- Optimize caching strategy
- Debug repeated calls

**Tracked metrics:**
- Total calls per session
- Calls by user (hashed)
- Calls by solution/table
- Calls by HTTP method
- Calls by endpoint

**Read more:** [API Statistics →](stats.md)

---

## Operation Patterns

### Cache-First Operations

These operations use intelligent caching by default (4-hour TTL):

**Cached:**
- `list_solutions`
- `list_tables`
- `get_table`
- `list_records` ⭐ (with local SQL filtering)
- `list_members`
- `list_teams`

**Not cached** (always fresh):
- `create_*` operations
- `update_*` operations
- `delete_*` operations
- `list_comments`
- `get_view_records`
- `analyze_solution_usage`

### Bypass Cache

Force fresh data from API:

```ruby
# Normal (uses cache)
list_records('tbl_123', 10, 0, fields: ['status'])

# Bypass cache
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true
)
```

**When to bypass:**
- Immediately after create/update/delete
- Need guaranteed fresh data
- Debugging cache issues

---

## Response Formats

### Plain Text (Token-Optimized)

Most operations return plain text instead of JSON for 30-50% token savings:

```
=== RECORDS (10 of 127 total) ===

--- Record 1 of 10 ---
id: rec_123abc
title: Q4 Planning
status: Active
priority: High

--- Record 2 of 10 ---
id: rec_456def
title: Budget Review
status: Pending
priority: Medium

[... etc]
```

### Structured Information

Operation responses include:
- **Total counts** - "X of Y total" for pagination decisions
- **Field values** - No truncation (request minimal fields)
- **Metadata** - IDs, timestamps, relationships
- **Status** - Success/error indicators

---

## Common Workflows

### Basic Data Query

```ruby
# 1. Find your solution
list_solutions

# 2. Get tables in solution
list_tables(solution_id: 'sol_abc123')

# 3. Get table structure
get_table('tbl_xyz789')

# 4. Query records
list_records('tbl_xyz789', 10, 0, fields: ['status', 'priority'])
```

### Create Records

```ruby
# 1. Get table structure (field slugs, required fields)
get_table('tbl_abc123')

# 2. Create record
create_record('tbl_abc123', {
  'title' => 'New Task',
  'status' => 'Active',
  'priority' => 5
})

# 3. Verify creation (bypass cache)
list_records('tbl_abc123', 10, 0,
  fields: ['title', 'status'],
  bypass_cache: true
)
```

### Filter and Update

```ruby
# 1. Find records matching criteria
list_records('tbl_tasks', 100, 0,
  fields: ['id', 'status', 'priority'],
  filter: {
    operator: 'and',
    fields: [
      {field: 'status', comparison: 'is', value: 'Pending'},
      {field: 'priority', comparison: 'is', value: 'High'}
    ]
  }
)

# 2. Update matching record
update_record('tbl_tasks', 'rec_found', {
  'status' => 'In Progress'
})
```

### Collaboration

```ruby
# 1. Find user
search_member('john@example.com')
# Returns: user_abc123

# 2. Add comment with assignment
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_task123',
  message: 'Please review by Friday',
  assigned_to: 'user_abc123'
)

# 3. Check comments
list_comments('rec_task123')
```

---

## Best Practices

### 1. Request Minimal Fields

**✅ Good:**
```ruby
list_records('tbl_123', 10, 0,
  fields: ['status', 'priority']  # Only what you need
)
```

**❌ Avoid:**
```ruby
list_records('tbl_123', 10, 0,
  fields: ['title', 'status', 'priority', 'description', 'notes', 'comments']
)
```

### 2. Leverage Caching

**✅ Good:**
```ruby
# Let cache work
list_records('tbl_123', 10, 0, fields: ['status'])
# ... later ...
list_records('tbl_123', 10, 10, fields: ['status'])  # Uses cache
```

**❌ Avoid:**
```ruby
# Bypass cache unnecessarily
list_records('tbl_123', 10, 0,
  fields: ['status'],
  bypass_cache: true  # Every time
)
```

### 3. Get Structure First

**✅ Good:**
```ruby
# Check structure
get_table('tbl_abc123')
# Use correct field slugs

# Create with correct slugs
create_record('tbl_abc123', {'s7e8c12e98' => 'Active'})
```

**❌ Avoid:**
```ruby
# Guess field slugs
create_record('tbl_abc123', {'status' => 'Active'})
# May error if slug is different
```

### 4. Use Appropriate Limits

**✅ Good:**
```ruby
# Start small
list_records('tbl_123', 10, 0, fields: ['status'])

# Scale up if needed
list_records('tbl_123', 50, 0, fields: ['status'])
```

**❌ Avoid:**
```ruby
# Fetch thousands at once
list_records('tbl_123', 5000, 0, fields: ['status'])
```

---

## Error Handling

All operations use consistent error reporting:

### Common Errors

**Not Found:**
```
Error: Table not found: tbl_xyz123
Error: Record not found: rec_xyz123
Error: Solution not found: sol_xyz123
```

**Permission Denied:**
```
Error: 403 Forbidden - Insufficient permissions
```

**Invalid Parameters:**
```
Error: Field 'xyz' not found in table
Error: Invalid filter structure
```

**Rate Limits:**
```
Error: 429 Too Many Requests
```

### Solutions

1. **Verify IDs** - Use list operations to confirm IDs
2. **Check permissions** - Verify access in SmartSuite
3. **Review structure** - Use `get_table` for field slugs
4. **Monitor stats** - Use `get_api_stats` for rate limits
5. **Enable caching** - Reduce API calls

---

## Related Documentation

### Getting Started
- [Installation Guide](../getting-started/installation.md)
- [Quick Start Tutorial](../getting-started/quick-start.md)
- [Troubleshooting Guide](../getting-started/troubleshooting.md)

### Guides
- [User Guide](../guides/user-guide.md)
- [Caching Guide](../guides/caching-guide.md)
- [Filtering Guide](../guides/filtering-guide.md)
- [Performance Guide](../guides/performance-guide.md)

### Reference
- [Field Types Reference](../reference/field-types.md)
- [Filter Operators Reference](../reference/filter-operators.md)
- [Error Codes](../reference/error-codes.md)

---

## Need Help?

- **[Troubleshooting Guide](../getting-started/troubleshooting.md)** - Common issues and solutions
- **[GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)** - Report bugs
- **[GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)** - Ask questions
- **[Examples](../../examples/)** - Practical usage patterns
