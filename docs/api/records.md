# Record Operations

Complete reference for record CRUD operations in SmartSuite.

## Overview

Records are rows in SmartSuite tables. The server provides full CRUD operations with intelligent caching support.

**Key Features:**
- Cache-first strategy (4-hour TTL)
- Local SQL filtering on cached data
- Plain text responses for token savings
- Automatic pagination support

---

## list_records

List records from a table with caching and filtering support.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier (e.g., `tbl_abc123`) |
| `limit` | integer | No | Max records to return (default: 10) |
| `offset` | integer | No | Pagination offset (default: 0) |
| `filter` | object | No | SmartSuite filter criteria |
| `sort` | array | No | Sort criteria |
| `fields` | array | ✅ Yes | Field slugs to return |
| `hydrated` | boolean | No | Fetch human-readable values (default: true) |
| `bypass_cache` | boolean | No | Force fresh API data (default: false) |

### Basic Example

```ruby
list_records(
  'tbl_6796989a7ee3c6b731717836',
  10,    # limit
  0,     # offset
  fields: ['status', 'priority', 'title']
)
```

### Response Format

```
=== RECORDS (10 of 127 total) ===

--- Record 1 of 10 ---
id: rec_68e3d5fb98c0282a4f1e2614
status: Active
priority: High
title: Q4 Planning

--- Record 2 of 10 ---
id: rec_68e3df1fd1cb4af2839cfd3c
status: Pending
priority: Medium
title: Budget Review

[... etc]
```

### With Filtering

```ruby
list_records(
  'tbl_6796989a7ee3c6b731717836',
  10,
  0,
  fields: ['status', 'priority'],
  filter: {
    operator: 'and',
    fields: [
      {field: 'status', comparison: 'is', value: 'Active'},
      {field: 'priority', comparison: 'is_greater_than', value: 3}
    ]
  }
)
```

### With Pagination

```ruby
# First page
list_records('tbl_abc123', 10, 0, fields: ['status'])

# Second page
list_records('tbl_abc123', 10, 10, fields: ['status'])

# Third page
list_records('tbl_abc123', 10, 20, fields: ['status'])
```

### Bypassing Cache

```ruby
# Get fresh data from API
list_records(
  'tbl_abc123',
  10,
  0,
  fields: ['status', 'priority'],
  bypass_cache: true
)
```

### Notes

- **Cache behavior:** Uses cache by default (4-hour TTL)
- **SmartSuite filters ignored** when using cache - filters applied locally via SQL
- **Response shows totals:** "X of Y total" helps with pagination decisions
- **No truncation:** Field values returned in full

---

## get_record

Retrieve a specific record by ID.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier (e.g., `rec_abc123`) |

### Example

```ruby
get_record(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614'
)
```

### Response Format

```
=== RECORD ===

id: rec_68e3d5fb98c0282a4f1e2614
title: Q4 Planning
status: Active
priority: High
assigned_to: John Doe
created_on: 2025-11-01T10:30:00Z
updated_on: 2025-11-15T14:22:00Z
```

### Notes

- Returns all fields (not filtered)
- Always fetches from API (not cached)
- Use `list_records` with filter if you want caching

---

## create_record

Create a new record in a table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `data` | object | ✅ Yes | Field values (field_slug: value) |

### Example

```ruby
create_record(
  'tbl_6796989a7ee3c6b731717836',
  {
    'title' => 'New Project',
    'status' => 'Active',
    'priority' => 'High',
    'assigned_to' => ['user_abc123']
  }
)
```

### Field Value Formats

**Text fields:**
```ruby
'title' => 'Project Name'
```

**Single select:**
```ruby
'status' => 'Active'
```

**Number fields:**
```ruby
'priority' => 5
```

**Date fields:**
```ruby
'due_date' => '2025-12-31'
```

**User fields:**
```ruby
'assigned_to' => ['user_abc123', 'user_def456']
```

**Linked records:**
```ruby
'related_project' => ['rec_xyz789']
```

### Response

Returns the created record with its new ID:

```
=== CREATED RECORD ===

id: rec_newid123
title: New Project
status: Active
priority: High
...
```

### Notes

- **Cache not invalidated:** New record won't appear in cache until TTL expires
- **Use bypass_cache** on next `list_records` if you need to see it immediately
- **Field slugs required:** Use field slugs, not labels

---

## update_record

Update an existing record.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier |
| `data` | object | ✅ Yes | Fields to update (field_slug: value) |

### Example

```ruby
update_record(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  {
    'status' => 'Completed',
    'priority' => 'Low'
  }
)
```

### Response

Returns the updated record:

```
=== UPDATED RECORD ===

id: rec_68e3d5fb98c0282a4f1e2614
title: Q4 Planning
status: Completed
priority: Low
...
```

### Notes

- **Partial updates:** Only include fields you want to change
- **Cache not invalidated:** Use `bypass_cache` to see changes immediately
- **Field validation:** SmartSuite validates field values

---

## delete_record

Delete a record from a table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier |

### Example

```ruby
delete_record(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614'
)
```

### Response

```
=== RECORD DELETED ===

Successfully deleted record: rec_68e3d5fb98c0282a4f1e2614
```

### Notes

- **Permanent deletion:** Cannot be undone
- **Cache not invalidated:** Deleted record may still appear in cache until TTL expires
- **Check permissions:** You must have delete permissions

---

## Common Patterns

### Get Table Structure First

Always get table structure before working with records:

```ruby
# 1. Get table structure
get_table('tbl_abc123')
# Returns: fields with slugs, labels, types

# 2. Then use correct field slugs
list_records('tbl_abc123', 10, 0,
  fields: ['s7e8c12e98', 's8f9d23a09']  // Use slugs from structure
)
```

### Create Then Read

After creating a record, fetch it fresh:

```ruby
# 1. Create record
create_record('tbl_abc123', {
  'status' => 'Active',
  'priority' => 'High'
})

# 2. See it immediately (bypass cache)
list_records('tbl_abc123', 10, 0,
  fields: ['status', 'priority'],
  bypass_cache: true
)
```

### Bulk Read Pattern

Process large datasets efficiently:

```ruby
# Process in batches
offset = 0
limit = 100

loop do
  records = list_records('tbl_abc123', limit, offset,
    fields: ['status', 'priority']
  )

  break if records.empty?

  # Process batch...

  offset += limit
end
```

---

## Best Practices

### 1. Request Minimal Fields

**✅ Good:**
```ruby
list_records('tbl_abc123', 10, 0,
  fields: ['status', 'priority']  // Only what you need
)
```

**❌ Avoid:**
```ruby
list_records('tbl_abc123', 10, 0,
  fields: ['title', 'status', 'priority', 'description', 'notes', 'comments']
)
```

### 2. Use Appropriate Limits

**✅ Good:**
```ruby
# Start small
list_records('tbl_abc123', 10, 0, fields: ['status'])

# Scale up if needed
list_records('tbl_abc123', 50, 0, fields: ['status'])
```

**❌ Avoid:**
```ruby
# Don't fetch thousands at once
list_records('tbl_abc123', 5000, 0, fields: ['status'])
```

### 3. Leverage the Cache

**✅ Good:**
```ruby
# Let cache work for you
list_records('tbl_abc123', 10, 0, fields: ['status'])
# ... later ...
list_records('tbl_abc123', 10, 10, fields: ['status'])  // Uses cache
```

**❌ Avoid:**
```ruby
# Don't bypass unnecessarily
list_records('tbl_abc123', 10, 0,
  fields: ['status'],
  bypass_cache: true  // Only when really needed
)
```

---

## Error Handling

### Table Not Found

```
Error: Table not found: tbl_xyz123
```

**Solution:** Verify table ID with `list_tables`

### Record Not Found

```
Error: Record not found: rec_xyz123
```

**Solution:** Record may be deleted, check with `list_records`

### Invalid Field

```
Error: Field 'xyz' not found in table
```

**Solution:** Use `get_table` to get correct field slugs

### Permission Denied

```
Error: 403 Forbidden - Insufficient permissions
```

**Solution:** Check SmartSuite permissions for table

---

## Related Documentation

- **[Filtering Guide](../guides/filtering-guide.md)** - Master filter syntax
- **[Caching Guide](../guides/caching-guide.md)** - Understand caching behavior
- **[Field Types Reference](../reference/field-types.md)** - All field types
- **[Filter Operators](../reference/filter-operators.md)** - Complete operator reference
- **[Performance Guide](../guides/performance-guide.md)** - Optimization tips

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
