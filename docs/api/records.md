# Record Operations

Complete reference for record operations in SmartSuite.

## Overview

Records are rows in SmartSuite tables. The server provides comprehensive record management including CRUD operations, bulk operations, file URL retrieval, and deleted records management.

**Key Features:**
- **CRUD Operations:** Create, read, update, delete individual records
- **Bulk Operations:** Efficient batch processing for multiple records
- **File Operations:** Get public URLs for file attachments
- **Deleted Records:** List and restore soft-deleted records
- **Cache-first Strategy:** 4-hour TTL for optimal performance
- **Local SQL Filtering:** Query cached data without API calls
- **TOON Format Responses:** Token-optimized output (50-60% savings vs JSON)

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
| `format` | string | No | Output format: `"toon"` (default) or `"json"` |

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

Default TOON format (50-60% token savings):

```
10 of 127 filtered (127 total)
records[10]{id|status|priority|title}:
rec_68e3d5fb98c0282a4f1e2614|Active|High|Q4 Planning
rec_68e3df1fd1cb4af2839cfd3c|Pending|Medium|Budget Review
rec_68e3e02a15fb8cd329a1e47f|Active|Low|Team Sync
[... etc]
```

Use `format: "json"` for JSON output if needed.

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
- **Use `refresh_cache` tool** if you need to see changes immediately: `refresh_cache('records', table_id: 'tbl_123')`
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
- **Cache not invalidated:** Use `refresh_cache('records', table_id: 'tbl_123')` to see changes immediately
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

- **Soft deletion:** Records are soft-deleted and can be restored via `restore_deleted_record`
- **Cache not invalidated:** Deleted record may still appear in cache until TTL expires
- **Check permissions:** You must have delete permissions

---

## bulk_add_records

Create multiple records in a single API call. More efficient than individual `create_record` calls.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `records` | array | ✅ Yes | Array of record data objects |

### Example

```ruby
bulk_add_records(
  'tbl_6796989a7ee3c6b731717836',
  [
    {
      'title' => 'Project Alpha',
      'status' => 'Active',
      'priority' => 'High'
    },
    {
      'title' => 'Project Beta',
      'status' => 'Pending',
      'priority' => 'Medium'
    },
    {
      'title' => 'Project Gamma',
      'status' => 'Active',
      'priority' => 'Low'
    }
  ]
)
```

### Response

Returns array of created records with IDs:

```
=== CREATED 3 RECORDS ===

Record 1:
id: rec_new123
title: Project Alpha
status: Active
priority: High

Record 2:
id: rec_new456
title: Project Beta
status: Pending
priority: Medium

Record 3:
id: rec_new789
title: Project Gamma
status: Active
priority: Low
```

### Notes

- **Performance:** Significantly faster than multiple `create_record` calls
- **Atomic operation:** All records created in single transaction
- **Cache not invalidated:** New records won't appear in cache until TTL expires

---

## bulk_update_records

Update multiple records in a single API call. Each record must include its `id` field.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `records` | array | ✅ Yes | Array of record updates (must include 'id' field) |

### Example

```ruby
bulk_update_records(
  'tbl_6796989a7ee3c6b731717836',
  [
    {
      'id' => 'rec_68e3d5fb98c0282a4f1e2614',
      'status' => 'Completed'
    },
    {
      'id' => 'rec_68e3df1fd1cb4af2839cfd3c',
      'status' => 'In Progress',
      'priority' => 'High'
    },
    {
      'id' => 'rec_68e3e02a15fb8cd329a1e47f',
      'priority' => 'Low'
    }
  ]
)
```

### Response

Returns array of updated records:

```
=== UPDATED 3 RECORDS ===

Record 1:
id: rec_68e3d5fb98c0282a4f1e2614
status: Completed
[... other fields]

Record 2:
id: rec_68e3df1fd1cb4af2839cfd3c
status: In Progress
priority: High
[... other fields]

Record 3:
id: rec_68e3e02a15fb8cd329a1e47f
priority: Low
[... other fields]
```

### Notes

- **Required 'id' field:** Each record object must include the 'id' field
- **Partial updates:** Only include fields you want to change (plus 'id')
- **Performance:** Much faster than multiple `update_record` calls
- **Cache not invalidated:** Changes won't appear in cache until TTL expires

---

## bulk_delete_records

Delete multiple records in a single API call. Performs soft deletion.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_ids` | array | ✅ Yes | Array of record IDs to delete |

### Example

```ruby
bulk_delete_records(
  'tbl_6796989a7ee3c6b731717836',
  [
    'rec_68e3d5fb98c0282a4f1e2614',
    'rec_68e3df1fd1cb4af2839cfd3c',
    'rec_68e3e02a15fb8cd329a1e47f'
  ]
)
```

### Response

```
=== DELETED 3 RECORDS ===

Successfully deleted records:
- rec_68e3d5fb98c0282a4f1e2614
- rec_68e3df1fd1cb4af2839cfd3c
- rec_68e3e02a15fb8cd329a1e47f
```

### Notes

- **Soft deletion:** Records can be restored via `restore_deleted_record`
- **Performance:** Much faster than multiple `delete_record` calls
- **Atomic operation:** All deletions in single transaction
- **Cache not invalidated:** Deleted records may still appear in cache until TTL expires

---

## get_file_url

Get a public URL for a file attached to a record. The URL has a 20-year lifetime.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_handle` | string | ✅ Yes | File handle from file/image field |

### Example

```ruby
# First, get a record with a file field
record = get_record('tbl_abc123', 'rec_xyz789')
# record['attachment'] might be: "handle_abc123xyz"

# Then get the public URL
get_file_url('handle_abc123xyz')
```

### Response

```json
{
  "url": "https://files.smartsuite.com/workspace/abc123/document.pdf"
}
```

### Notes

- **File handles** can be found in file/image field values
- **Long-lived URLs:** Generated URLs valid for 20 years
- **Direct access:** URLs can be used directly to download files
- **No authentication:** Public URLs don't require API authentication

---

## attach_file

Attach files to a record by providing URLs. SmartSuite downloads files from the provided URLs and attaches them to the specified file/image field.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier |
| `file_field_slug` | string | ✅ Yes | Slug of the file/image field |
| `file_urls` | array | ✅ Yes | Array of publicly accessible file URLs |

### Example

```ruby
# Attach a single file
attach_file(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'attachments',
  ['https://example.com/document.pdf']
)

# Attach multiple files
attach_file(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'images',
  [
    'https://example.com/image1.jpg',
    'https://example.com/image2.jpg',
    'https://example.com/image3.png'
  ]
)
```

### Response

```json
{
  "id": "rec_68e3d5fb98c0282a4f1e2614",
  "title": "Document Record",
  "attachments": [
    {
      "url": "https://files.smartsuite.com/...",
      "name": "document.pdf",
      "size": 1024000,
      "type": "application/pdf"
    }
  ]
}
```

### Notes

- **Public URLs required:** File URLs must be publicly accessible for SmartSuite to download
- **SmartSuite downloads files:** The API fetches files from provided URLs and stores them
- **Supported formats:** All file types supported by SmartSuite file/image fields
- **Uses update endpoint:** Internally uses PATCH to update the file field
- **Cache not invalidated:** Updated record may not appear in cache until TTL expires

### Security Considerations

⚠️ **Important:** The `attach_file` API requires publicly accessible URLs, which can pose security risks for sensitive files.

**Recommended Solution: Use `SecureFileAttacher`**

For secure file attachment, use the included `SecureFileAttacher` helper class which:
- Uploads files to AWS S3 with encryption
- Generates short-lived pre-signed URLs (default: 2 minutes)
- Automatically deletes files after SmartSuite fetches them
- Never exposes files publicly

```ruby
require_relative 'lib/secure_file_attacher'

# Initialize secure attacher
attacher = SecureFileAttacher.new(client, 'my-temp-bucket')

# Attach local files securely
attacher.attach_file_securely(
  'tbl_123',
  'rec_456',
  'attachments',
  './sensitive_document.pdf'
)
```

**See:**
- `lib/secure_file_attacher.rb` - Full implementation
- `examples/secure_file_attachment.rb` - Complete usage examples
- `docs/guides/secure-file-attachment.md` - Setup guide

---

## list_deleted_records

List all soft-deleted records from a solution. Useful for recovery or cleanup.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `solution_id` | string | ✅ Yes | Solution identifier |
| `preview` | boolean | No | Limit returned fields (default: true) |

### Example

```ruby
# List deleted records with limited fields
list_deleted_records('sol_6796981c7ae3b5a624e16f2d', preview: true)

# List with all fields
list_deleted_records('sol_6796981c7ae3b5a624e16f2d', preview: false)
```

### Response

```
=== DELETED RECORDS (15 found) ===

Record 1:
id: rec_68e3d5fb98c0282a4f1e2614
title: Old Project
deleted_at: 2025-11-10T15:30:00Z
deleted_by: user_abc123

Record 2:
id: rec_68e3df1fd1cb4af2839cfd3c
title: Archived Task
deleted_at: 2025-11-05T10:20:00Z
deleted_by: user_def456

[... more records]
```

### Notes

- **Preview mode:** When `preview: true`, returns limited fields for efficiency
- **All fields:** When `preview: false`, returns complete record data
- **Deletion metadata:** Includes `deleted_at` and `deleted_by` information
- **Solution-wide:** Lists deleted records across all tables in the solution

---

## restore_deleted_record

Restore a soft-deleted record back to its table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier to restore |

### Example

```ruby
# First, find deleted records
deleted = list_deleted_records('sol_abc123')
# Identifies: rec_68e3d5fb98c0282a4f1e2614

# Then restore a specific record
restore_deleted_record(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614'
)
```

### Response

```
=== RESTORED RECORD ===

id: rec_68e3d5fb98c0282a4f1e2614
title: Old Project
status: Active
restored_at: 2025-11-17T12:00:00Z
[... other fields]
```

### Notes

- **Full restoration:** All field values are preserved
- **Cache not updated:** Restored record won't appear in cache until TTL expires
- **Permissions:** Requires appropriate permissions on the table

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

# 2. Wait for cache to expire (4 hours) or refresh cache manually
# Cache will automatically reflect new data after TTL expires
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
# Let cache work for you (4-hour TTL)
list_records('tbl_abc123', 10, 0, fields: ['status'])
# ... later ...
list_records('tbl_abc123', 10, 10, fields: ['status'])  // Uses cache - no API call
```

**✅ Also Good:**
```ruby
# Use bulk operations for efficiency
bulk_add_records('tbl_abc123', [
  {'title' => 'Task 1', 'status' => 'Active'},
  {'title' => 'Task 2', 'status' => 'Active'}
])
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
