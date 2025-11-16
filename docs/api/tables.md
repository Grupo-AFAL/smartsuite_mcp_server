# Table Operations

Complete reference for SmartSuite table (application) operations.

## Overview

Tables (also called "applications" in the API) are the containers for records within solutions. Each table has a defined structure with fields, and contains rows of data (records).

**Key Features:**
- List tables across all solutions or filter by solution
- Get table structure (fields, field types, slugs)
- Create new tables with custom fields
- Cache-first strategy (4-hour TTL)
- Filtered structures to minimize tokens

---

## list_tables

List all tables (applications) in your workspace, optionally filtered by solution.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `solution_id` | string | No | Filter tables by solution ID |
| `fields` | array | No | Field slugs to include in response |

### Basic Example

```ruby
# List all tables across all solutions
list_tables
```

### Response Format

```
=== TABLES (25 total) ===

--- Table 1 of 25 ---
id: tbl_123abc456def
name: Customers
solution_id: sol_xyz789

--- Table 2 of 25 ---
id: tbl_789ghi012jkl
name: Orders
solution_id: sol_xyz789

[... etc]
```

### Filter by Solution

```ruby
# List tables in specific solution
list_tables(solution_id: 'sol_xyz789')
```

Returns:

```
=== TABLES in solution sol_xyz789 (5 total) ===

--- Table 1 of 5 ---
id: tbl_123abc
name: Customers
solution_id: sol_xyz789

--- Table 2 of 5 ---
id: tbl_456def
name: Orders
solution_id: sol_xyz789

[... etc]
```

### Request Specific Fields

```ruby
# Request additional fields
list_tables(fields: ['id', 'name', 'structure', 'solution_id'])
```

**Available fields:**
- `id` - Table identifier (always included)
- `name` - Table name (always included)
- `solution_id` - Parent solution ID (always included)
- `structure` - Complete field structure (large)
- `slug` - URL-friendly identifier
- `description` - Table description
- `created` - Creation timestamp
- `updated` - Last update timestamp
- `record_count` - Number of records
- `permissions` - Permissions object

**Note:** When `fields` parameter is NOT specified, server returns only essential fields (id, name, solution_id) for token efficiency.

### Notes

- **Cache enabled** by default (4-hour TTL)
- **Essential fields only** when `fields` not specified
- **Use `solution_id` filter** for efficient solution-specific queries
- **Avoid requesting `structure`** unless needed (very large)

---

## get_table

Get a specific table's structure including field definitions.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |

### Example

```ruby
get_table('tbl_6796989a7ee3c6b731717836')
```

### Response Format

```
=== TABLE STRUCTURE ===

id: tbl_6796989a7ee3c6b731717836
name: Projects
solution_id: sol_abc123def456

Fields (12):

--- Field 1: Title ---
slug: title
label: Title
field_type: textfield
required: true
primary: false

--- Field 2: Status ---
slug: s7e8c12e98
label: Status
field_type: singleselectfield
required: false
primary: false
choices:
  - Active
  - Pending
  - Completed
  - Cancelled

--- Field 3: Priority ---
slug: s8f9d23a09
label: Priority
field_type: numberfield
required: false
primary: false

[... etc for all fields]
```

### Field Information Returned

For each field:
- `slug` - Field identifier (use for queries)
- `label` - Display name
- `field_type` - Field type (textfield, numberfield, etc.)
- `required` - Whether field is required
- `primary` - Whether field is primary key
- `unique` - Whether values must be unique
- `choices` - Options for select fields (minimal - value only)
- `linked_application` - Target table for linked record fields
- `entries_allowed` - Single/multiple entries allowed

**Token optimization:** Structure is filtered to remove 83.8% of UI/display metadata (colors, icons, display formats, column widths, etc.)

### Use Cases

**1. Discover Field Slugs:**
```ruby
# Get table structure
get_table('tbl_abc123')
# Use slugs in queries
list_records('tbl_abc123', 10, 0, fields: ['s7e8c12e98', 's8f9d23a09'])
```

**2. Understand Field Types:**
```ruby
# Check field types before filtering
get_table('tbl_abc123')
# Use correct operators for field type
# (e.g., `is` for single select, `has_any_of` for linked records)
```

**3. Find Required Fields:**
```ruby
# Before creating records, check required fields
get_table('tbl_abc123')
# Include all required fields in create_record
```

### Notes

- **Cache enabled** (4-hour TTL)
- **Filtered structure** (only essential field info)
- **Always run before** creating/updating records
- **Use slugs** from response for field references

---

## create_table

Create a new table in a solution.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `solution_id` | string | ✅ Yes | Parent solution ID |
| `name` | string | ✅ Yes | Table name |
| `description` | string | No | Table description |
| `structure` | array | No | Field definitions (if not provided, empty array used) |

### Basic Example

```ruby
# Create empty table
create_table(
  solution_id: 'sol_abc123',
  name: 'New Projects'
)
```

### With Description

```ruby
create_table(
  solution_id: 'sol_abc123',
  name: 'Customer Feedback',
  description: 'Track customer feedback and feature requests'
)
```

### With Fields

```ruby
create_table(
  solution_id: 'sol_abc123',
  name: 'Task Tracker',
  structure: [
    {
      slug: 'title',
      label: 'Task Title',
      field_type: 'textfield',
      params: {
        required: true
      }
    },
    {
      slug: 's123abc456',
      label: 'Status',
      field_type: 'singleselectfield',
      params: {
        choices: [
          {value: 'To Do'},
          {value: 'In Progress'},
          {value: 'Done'}
        ]
      }
    }
  ]
)
```

### Field Structure Format

Each field requires:

**Required:**
- `slug` - Unique field identifier (e.g., 's123abc456')
- `label` - Display name
- `field_type` - Field type (see [Field Types Reference](../reference/field-types.md))
- `params` - Field configuration object

**Optional:**
- `is_new` - Set to `true` for new fields (default: true)
- `icon` - Icon name
- `required` - Required field flag (in params)

### Common Field Types

**Text Field:**
```ruby
{
  slug: 'description',
  label: 'Description',
  field_type: 'textfield',
  params: {
    required: false,
    help_text: 'Enter task description'
  }
}
```

**Number Field:**
```ruby
{
  slug: 'priority',
  label: 'Priority',
  field_type: 'numberfield',
  params: {
    required: false,
    decimal_places: 0,
    min_value: 1,
    max_value: 10
  }
}
```

**Single Select:**
```ruby
{
  slug: 'status',
  label: 'Status',
  field_type: 'singleselectfield',
  params: {
    choices: [
      {value: 'Active'},
      {value: 'Inactive'}
    ]
  }
}
```

**Date Field:**
```ruby
{
  slug: 'due_date',
  label: 'Due Date',
  field_type: 'duedatefield',
  params: {
    required: false,
    time_format: 'h:mm A',
    date_format: 'MM/DD/YYYY'
  }
}
```

**Linked Record:**
```ruby
{
  slug: 'related_project',
  label: 'Related Project',
  field_type: 'linkedrecordfield',
  params: {
    linked_application: 'tbl_xyz789',
    entries_allowed: 'multiple'
  }
}
```

### Response Format

Returns the created table with its ID:

```
=== TABLE CREATED ===

id: tbl_new123abc
name: Task Tracker
solution_id: sol_abc123
description: null

Created successfully!
```

### Notes

- **No cache invalidation** - new table won't appear in cache until TTL expires
- **Use bypass_cache** on next `list_tables` to see it immediately
- **Structure optional** - can create empty table and add fields later
- **Field slugs must be unique** within the table
- See [Field Operations](fields.md) for adding fields to existing tables

---

## Common Patterns

### Get Solution Tables

```ruby
# 1. List solutions to find solution_id
list_solutions

# 2. Get tables in that solution
list_tables(solution_id: 'sol_abc123')

# 3. Get structure of specific table
get_table('tbl_xyz789')
```

### Before Creating Records

Always get table structure first to know:
- Available field slugs
- Required fields
- Field types (for correct value formats)

```ruby
# 1. Get table structure
get_table('tbl_abc123')
# Response shows: title (required), status (optional), priority (optional)

# 2. Create record with required fields
create_record('tbl_abc123', {
  'title' => 'New Task',
  'status' => 'Active',
  'priority' => 5
})
```

### Create Table with Standard Fields

```ruby
# Create table with common fields
create_table(
  solution_id: 'sol_abc123',
  name: 'Contacts',
  structure: [
    {
      slug: 'full_name',
      label: 'Full Name',
      field_type: 'fullnamefield',
      params: {required: true}
    },
    {
      slug: 'email',
      label: 'Email',
      field_type: 'emailfield',
      params: {required: true, unique: true}
    },
    {
      slug: 'phone',
      label: 'Phone',
      field_type: 'phonefield',
      params: {required: false}
    },
    {
      slug: 'status',
      label: 'Status',
      field_type: 'singleselectfield',
      params: {
        choices: [
          {value: 'Active'},
          {value: 'Inactive'}
        ]
      }
    }
  ]
)
```

---

## Best Practices

### 1. Filter Tables by Solution

**✅ Good:**
```ruby
# Filter at API level
list_tables(solution_id: 'sol_abc123')
```

**❌ Avoid:**
```ruby
# Fetch all tables then filter manually
list_tables  # Returns 100+ tables
# Then manually filter in conversation
```

### 2. Don't Request Structure Unless Needed

**✅ Good:**
```ruby
# Default essential fields only
list_tables(solution_id: 'sol_abc123')

# Get structure when needed
get_table('tbl_specific')
```

**❌ Avoid:**
```ruby
# Structure is very large (thousands of lines per table)
list_tables(fields: ['id', 'name', 'structure'])  # Token waste
```

### 3. Use get_table Before Working with Records

**✅ Good:**
```ruby
# Always check structure first
get_table('tbl_abc123')
# Use correct field slugs
list_records('tbl_abc123', 10, 0, fields: ['s7e8c12e98', 'title'])
```

**❌ Avoid:**
```ruby
# Guessing field slugs
list_records('tbl_abc123', 10, 0, fields: ['status', 'priority'])
# May error if slugs are wrong
```

### 4. Plan Field Structure Before Creating

**✅ Good:**
```ruby
# Define structure upfront
structure = [
  {slug: 'title', label: 'Title', field_type: 'textfield', params: {required: true}},
  {slug: 'status', label: 'Status', field_type: 'singleselectfield', params: {...}}
]
create_table(solution_id: 'sol_123', name: 'Tasks', structure: structure)
```

**❌ Avoid:**
```ruby
# Creating empty table then adding many fields one by one
create_table(solution_id: 'sol_123', name: 'Tasks')
add_field('tbl_new', ...)  # Repeat 10+ times
```

Use `bulk_add_fields` if you need to add many fields to existing table.

---

## Error Handling

### Solution Not Found

```
Error: Solution not found: sol_xyz123
```

**Solution:** Verify solution ID with `list_solutions`

### Table Not Found

```
Error: Table not found: tbl_xyz123
```

**Solution:** Verify table ID with `list_tables`

### Invalid Field Structure

```
Error: Invalid field type: invalidtype
```

**Solution:** Check [Field Types Reference](../reference/field-types.md) for valid types

### Duplicate Field Slug

```
Error: Field slug 'title' already exists
```

**Solution:** Use unique slugs for each field (e.g., 's123abc456')

---

## Related Documentation

- **[Field Operations](fields.md)** - Add/update/delete fields in tables
- **[Record Operations](records.md)** - Work with data in tables
- **[Workspace Operations](workspace.md)** - Manage solutions
- **[Field Types Reference](../reference/field-types.md)** - Complete field type guide
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
