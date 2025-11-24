# Field Operations

Complete reference for SmartSuite field (schema) operations.

## Overview

Fields define the structure of your tables - they're the columns that hold data in each record. The server provides full CRUD operations for managing table fields.

**Key Features:**
- Add individual fields to tables
- Bulk add multiple fields at once
- Update existing field configurations
- Delete fields permanently
- Rich text help documentation support

---

## add_field

Add a new field to an existing table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `field_data` | object | ✅ Yes | Field configuration |
| `field_position` | object | No | Position metadata (default: `{}`) |

### Basic Example

```ruby
add_field(
  'tbl_6796989a7ee3c6b731717836',
  {
    slug: 's123abc456def',
    label: 'Department',
    field_type: 'singleselectfield',
    params: {
      choices: [
        {value: 'Engineering'},
        {value: 'Sales'},
        {value: 'Marketing'}
      ]
    },
    is_new: true
  }
)
```

### Field Data Structure

**Required fields:**
- `slug` - Unique field identifier (e.g., 's123abc456')
- `label` - Display name
- `field_type` - Field type (see [Field Types Reference](../reference/field-types.md))
- `params` - Field configuration object
- `is_new` - Set to `true` for new fields

**Optional fields:**
- `icon` - Icon name
- `help_doc` - Help text (rich text format)
- `display_format` - Display format configuration

### Common Field Types

**Text Field:**
```ruby
{
  slug: 'notes',
  label: 'Notes',
  field_type: 'textareafield',
  params: {
    required: false,
    help_text: 'Additional notes or comments'
  },
  is_new: true
}
```

**Number Field:**
```ruby
{
  slug: 'budget',
  label: 'Budget',
  field_type: 'currencyfield',
  params: {
    required: false,
    decimal_places: 2,
    currency_symbol: '$'
  },
  is_new: true
}
```

**Single Select:**
```ruby
{
  slug: 'priority',
  label: 'Priority',
  field_type: 'singleselectfield',
  params: {
    required: true,
    choices: [
      {value: 'Low'},
      {value: 'Medium'},
      {value: 'High'},
      {value: 'Critical'}
    ]
  },
  is_new: true
}
```

**Multiple Select:**
```ruby
{
  slug: 'tags',
  label: 'Tags',
  field_type: 'multipleselectfield',
  params: {
    required: false,
    choices: [
      {value: 'urgent'},
      {value: 'bug'},
      {value: 'feature'},
      {value: 'enhancement'}
    ]
  },
  is_new: true
}
```

**Date Field:**
```ruby
{
  slug: 'deadline',
  label: 'Deadline',
  field_type: 'duedatefield',
  params: {
    required: false,
    time_format: 'h:mm A',
    date_format: 'MM/DD/YYYY',
    include_time: true
  },
  is_new: true
}
```

**Linked Record:**
```ruby
{
  slug: 'assigned_to',
  label: 'Assigned To',
  field_type: 'linkedrecordfield',
  params: {
    linked_application: 'tbl_users123',
    entries_allowed: 'single'  # or 'multiple'
  },
  is_new: true
}
```

**Yes/No (Boolean):**
```ruby
{
  slug: 'is_active',
  label: 'Active',
  field_type: 'yesnofield',
  params: {
    required: false,
    default_value: true
  },
  is_new: true
}
```

### Help Documentation

Add rich text help that appears below the field:

```ruby
add_field(
  'tbl_abc123',
  {
    slug: 's123abc',
    label: 'Project Code',
    field_type: 'textfield',
    params: {
      required: true,
      help_doc: {
        data: {
          type: 'doc',
          content: [
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: 'Use format: PROJ-YYYY-####'
                }
              ]
            }
          ]
        },
        html: '<p>Use format: PROJ-YYYY-####</p>',
        preview: 'Use format: PROJ-YYYY-####',
        display_format: 'tooltip'  # or 'inline'
      }
    },
    is_new: true
  }
)
```

### Field Positioning

Place field after another field:

```ruby
add_field(
  'tbl_abc123',
  {
    slug: 'snew123',
    label: 'New Field',
    field_type: 'textfield',
    params: {},
    is_new: true
  },
  field_position: {
    prev_sibling_slug: 'sexisting456'  # Place after this field
  }
)
```

### Response

Returns empty object `{}` on success:

```
=== FIELD ADDED ===

Successfully added field to table tbl_abc123
```

### Notes

- **No cache invalidation** - table structure cache not updated
- **Use `refresh_cache('tables')`** to see changes immediately
- **Field slugs must be unique** within the table
- **auto_fill_structure_layout** defaults to `true` (automatic layout)

---

## bulk_add_fields

Add multiple fields to a table in one request.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `fields` | array | ✅ Yes | Array of field configurations |
| `set_as_visible_fields_in_reports` | array | No | View IDs where fields should be visible |

### Example

```ruby
bulk_add_fields(
  'tbl_abc123',
  fields: [
    {
      slug: 's1new',
      label: 'First Name',
      field_type: 'textfield',
      params: {required: true},
      is_new: true
    },
    {
      slug: 's2new',
      label: 'Last Name',
      field_type: 'textfield',
      params: {required: true},
      is_new: true
    },
    {
      slug: 's3new',
      label: 'Email',
      field_type: 'emailfield',
      params: {required: true, unique: true},
      is_new: true
    },
    {
      slug: 's4new',
      label: 'Status',
      field_type: 'singleselectfield',
      params: {
        choices: [
          {value: 'Active'},
          {value: 'Inactive'}
        ]
      },
      is_new: true
    }
  ]
)
```

### With Visible Fields in Views

```ruby
bulk_add_fields(
  'tbl_abc123',
  fields: [...],
  set_as_visible_fields_in_reports: ['view_abc123', 'view_def456']
)
```

### Limitations

**Unsupported field types in bulk operations:**
- Formula fields (`formulafield`)
- Count fields (`countfield`)
- Time tracking fields (`timetrackingfield`)

These must be added individually using `add_field`.

### Response

Returns array of created field objects:

```
=== FIELDS ADDED ===

Successfully added 4 fields to table tbl_abc123:
- First Name (s1new)
- Last Name (s2new)
- Email (s3new)
- Status (s4new)
```

### Use Cases

**1. Initialize New Table:**
```ruby
# Create table
create_table(solution_id: 'sol_123', name: 'Contacts')

# Add all fields at once
bulk_add_fields('tbl_new123', fields: [
  # All contact fields...
])
```

**2. Migrate Schema:**
```ruby
# Copy fields from one table to another
# (Get structure from source, adapt, bulk add to target)
```

### Notes

- **More efficient** than multiple `add_field` calls
- **Same cache behavior** - no invalidation
- **Check field type support** before using bulk operation
- **Use individual add_field** for formula/count/timetracking fields

---

## update_field

Update an existing field's configuration.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `slug` | string | ✅ Yes | Field slug to update |
| `field_data` | object | ✅ Yes | Updated field configuration |

### Example

```ruby
update_field(
  'tbl_abc123',
  's7e8c12e98',
  {
    label: 'Project Status',  # Change label
    field_type: 'singleselectfield',
    params: {
      required: true,  # Make required
      choices: [
        {value: 'Planning'},
        {value: 'In Progress'},
        {value: 'On Hold'},
        {value: 'Completed'},
        {value: 'Cancelled'}
      ]
    }
  }
)
```

### What Can Be Updated

**Label:**
```ruby
update_field('tbl_123', 's_field', {
  label: 'New Label',
  field_type: 'textfield',
  params: {...}
})
```

**Required Status:**
```ruby
update_field('tbl_123', 's_field', {
  label: 'Field Name',
  field_type: 'textfield',
  params: {
    required: true  # Make required
  }
})
```

**Select Field Choices:**
```ruby
update_field('tbl_123', 's_status', {
  label: 'Status',
  field_type: 'singleselectfield',
  params: {
    choices: [
      {value: 'Active'},
      {value: 'Inactive'},
      {value: 'Archived'}  # Add new choice
    ]
  }
})
```

**Help Documentation:**
```ruby
update_field('tbl_123', 's_field', {
  label: 'Field Name',
  field_type: 'textfield',
  params: {
    help_doc: {
      data: {...},
      html: '<p>New help text</p>',
      preview: 'New help text',
      display_format: 'inline'
    }
  }
})
```

### Field Data Structure

**Always include:**
- `label` - Current or new label
- `field_type` - Field type (must match existing)
- `params` - Complete params object (merged with existing)

**Note:** The `slug` is automatically merged from the parameter into the field_data body.

### Response

Returns the updated field object:

```
=== FIELD UPDATED ===

Successfully updated field s7e8c12e98 in table tbl_abc123

slug: s7e8c12e98
label: Project Status
field_type: singleselectfield
required: true
choices:
  - Planning
  - In Progress
  - On Hold
  - Completed
  - Cancelled
```

### Notes

- **No cache invalidation** - table structure cache not updated
- **Cannot change field type** - must delete and recreate
- **Cannot change slug** - slug is the identifier
- **HTTP method is PUT** (not POST)

---

## delete_field

Delete a field from a table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `slug` | string | ✅ Yes | Field slug to delete |

### Example

```ruby
delete_field('tbl_abc123', 's7e8c12e98')
```

### Response

Returns the deleted field object:

```
=== FIELD DELETED ===

Successfully deleted field s7e8c12e98 from table tbl_abc123

slug: s7e8c12e98
label: Old Field
field_type: textfield
```

### ⚠️ Warning

**This operation is permanent and cannot be undone!**
- All data in this field will be lost
- Records will no longer have this field
- No backup is created

**Before deleting:**
1. Verify you have the correct field slug
2. Consider exporting data if needed
3. Check if field is used in formulas or automations
4. Confirm with stakeholders

### Notes

- **No cache invalidation** - table structure cache not updated
- **Permanent deletion** - data cannot be recovered
- **Check dependencies** before deleting (formulas, linked fields, etc.)

---

## Common Patterns

### Add Field with Standard Configuration

```ruby
# 1. Get table structure to understand existing fields
get_table('tbl_abc123')

# 2. Add new field with proper configuration
add_field('tbl_abc123', {
  slug: 's_new_field',
  label: 'New Field',
  field_type: 'textfield',
  params: {
    required: false,
    help_text: 'Enter value here'
  },
  is_new: true
})

# 3. Verify field was added (refresh cache first)
refresh_cache('tables')
get_table('tbl_abc123')
```

### Update Select Field Choices

```ruby
# 1. Get current field structure
get_table('tbl_abc123')
# Note current choices

# 2. Update with new choices
update_field('tbl_abc123', 's_status', {
  label: 'Status',
  field_type: 'singleselectfield',
  params: {
    choices: [
      {value: 'Active'},
      {value: 'Inactive'},
      {value: 'Archived'}  # Add new option
    ]
  }
})
```

### Initialize Table with Multiple Fields

```ruby
# 1. Create empty table
create_table(solution_id: 'sol_123', name: 'Projects')
# Returns: {id: 'tbl_new123'}

# 2. Add all fields at once
bulk_add_fields('tbl_new123', fields: [
  {
    slug: 's_title',
    label: 'Project Title',
    field_type: 'textfield',
    params: {required: true},
    is_new: true
  },
  {
    slug: 's_status',
    label: 'Status',
    field_type: 'singleselectfield',
    params: {
      required: true,
      choices: [
        {value: 'Planning'},
        {value: 'Active'},
        {value: 'Completed'}
      ]
    },
    is_new: true
  },
  {
    slug: 's_budget',
    label: 'Budget',
    field_type: 'currencyfield',
    params: {
      required: false,
      decimal_places: 2,
      currency_symbol: '$'
    },
    is_new: true
  }
])
```

### Change Field to Required

```ruby
# 1. Get current configuration
get_table('tbl_abc123')

# 2. Update field to make it required
update_field('tbl_abc123', 's_field', {
  label: 'Field Name',
  field_type: 'textfield',
  params: {
    required: true  # Change to required
  }
})

# 3. Update any records missing values
# (SmartSuite may reject the change if records have empty values)
```

---

## Best Practices

### 1. Get Table Structure First

**✅ Good:**
```ruby
# Check existing fields first
get_table('tbl_abc123')

# Add field with unique slug
add_field('tbl_abc123', {
  slug: 's_unique_new',  # Unique slug
  ...
})
```

**❌ Avoid:**
```ruby
# Don't add without checking
add_field('tbl_abc123', {
  slug: 'title',  # May conflict with existing field
  ...
})
```

### 2. Use Bulk Operations When Possible

**✅ Good:**
```ruby
# Add multiple fields at once
bulk_add_fields('tbl_123', fields: [
  # All fields...
])
```

**❌ Avoid:**
```ruby
# Multiple individual calls
add_field('tbl_123', field1)
add_field('tbl_123', field2)
add_field('tbl_123', field3)
# etc. (slow, many API calls)
```

### 3. Include Complete Configuration

**✅ Good:**
```ruby
update_field('tbl_123', 's_field', {
  label: 'Status',
  field_type: 'singleselectfield',
  params: {
    required: true,
    choices: [...]  # All choices
  }
})
```

**❌ Avoid:**
```ruby
# Incomplete update (may lose config)
update_field('tbl_123', 's_field', {
  label: 'New Label'  # Missing field_type, params
})
```

### 4. Verify Before Deleting

**✅ Good:**
```ruby
# Get table structure
get_table('tbl_abc123')
# Verify correct field slug

# Confirm deletion
delete_field('tbl_abc123', 's_correct_field')
```

**❌ Avoid:**
```ruby
# Delete without verification
delete_field('tbl_abc123', 's_field')  # Wrong field?
```

---

## Error Handling

### Table Not Found

```
Error: Table not found: tbl_xyz123
```

**Solution:** Verify table ID with `list_tables`

### Field Not Found

```
Error: Field 'xyz' not found in table
```

**Solution:** Use `get_table` to get correct field slugs

### Duplicate Field Slug

```
Error: Field slug 's123' already exists
```

**Solution:** Use unique slug for new field

### Invalid Field Type

```
Error: Invalid field type: invalidtype
```

**Solution:** Check [Field Types Reference](../reference/field-types.md)

### Field Type Not Supported in Bulk

```
Error: Formula fields not supported in bulk operation
```

**Solution:** Use individual `add_field` for formula/count/timetracking fields

---

## Related Documentation

- **[Table Operations](tables.md)** - Create and manage tables
- **[Record Operations](records.md)** - Work with data
- **[Field Types Reference](../reference/field-types.md)** - Complete field type guide
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
