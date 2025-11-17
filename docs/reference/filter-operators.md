# Filter Operators Reference

Complete reference guide for all SmartSuite filter operators organized by field type.

## Quick Reference Table

| Field Type | Operators | Values |
|------------|-----------|--------|
| Text | `is`, `is_not`, `contains`, `not_contains`, `is_empty`, `is_not_empty` | String |
| Number | `is_equal_to`, `is_not_equal_to`, `is_greater_than`, `is_less_than`, `is_equal_or_greater_than`, `is_equal_or_less_than`, `is_empty`, `is_not_empty` | Numeric |
| Single Select | `is`, `is_not`, `is_any_of`, `is_none_of`, `is_empty`, `is_not_empty` | String or Array |
| Multiple Select | `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty` | Array |
| Date | `is`, `is_not`, `is_before`, `is_on_or_before`, `is_after`, `is_empty`, `is_not_empty` | Date Object |
| Linked Record | `contains`, `not_contains`, `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty` | Array (IDs) |
| User | `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty` | Array (User IDs) |
| Boolean | `is`, `is_empty`, `is_not_empty` | Boolean |
| File | `file_name_contains`, `file_type_is`, `is_empty`, `is_not_empty` | String |

---

## Text-Based Fields

**Field Types:** Text, Email, Phone, Full Name, Address, Link, Text Area

### Operators

#### `is`
Exact match (case-sensitive)

```ruby
{field: 'email', comparison: 'is', value: 'john@example.com'}
```

#### `is_not`
Not equal to

```ruby
{field: 'status', comparison: 'is_not', value: 'Cancelled'}
```

#### `contains`
Contains substring (case-insensitive)

```ruby
{field: 'email', comparison: 'contains', value: 'example.com'}
```

#### `not_contains`
Doesn't contain substring

```ruby
{field: 'description', comparison: 'not_contains', value: 'deprecated'}
```

#### `is_empty`
Field has no value

```ruby
{field: 'notes', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Field has a value

```ruby
{field: 'email', comparison: 'is_not_empty', value: nil}
```

---

## Number Fields

**Field Types:** Number, Currency, Rating, Percent, Duration, Auto Number

### Operators

#### `is_equal_to`
Equals exactly

```ruby
{field: 'quantity', comparison: 'is_equal_to', value: 100}
```

#### `is_not_equal_to`
Not equal to

```ruby
{field: 'price', comparison: 'is_not_equal_to', value: 0}
```

#### `is_greater_than`
Greater than (>)

```ruby
{field: 'budget', comparison: 'is_greater_than', value: 10000}
```

#### `is_less_than`
Less than (<)

```ruby
{field: 'stock', comparison: 'is_less_than', value: 10}
```

#### `is_equal_or_greater_than`
Greater than or equal (>=)

```ruby
{field: 'score', comparison: 'is_equal_or_greater_than', value: 80}
```

#### `is_equal_or_less_than`
Less than or equal (<=)

```ruby
{field: 'age', comparison: 'is_equal_or_less_than', value: 65}
```

#### `is_empty`
No value set

```ruby
{field: 'discount', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has a value

```ruby
{field: 'price', comparison: 'is_not_empty', value: nil}
```

---

## Single Select / Status Fields

**Field Types:** Single Select, Status, Dropdown

### Operators

#### `is`
Equals option

```ruby
{field: 'status', comparison: 'is', value: 'Active'}
```

#### `is_not`
Not this option

```ruby
{field: 'status', comparison: 'is_not', value: 'Archived'}
```

#### `is_any_of`
Matches any in list

```ruby
{field: 'status', comparison: 'is_any_of', value: ['Active', 'Pending']}
```

#### `is_none_of`
Matches none in list

```ruby
{field: 'status', comparison: 'is_none_of', value: ['Cancelled', 'Deleted']}
```

#### `is_empty`
No selection made

```ruby
{field: 'department', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has a selection

```ruby
{field: 'priority', comparison: 'is_not_empty', value: nil}
```

---

## Multiple Select / Tags Fields

**Field Types:** Multiple Select, Tags

### Operators

#### `has_any_of`
Contains at least one of these

```ruby
{field: 'tags', comparison: 'has_any_of', value: ['urgent', 'bug']}
```

**Matches:** Records with "urgent" OR "bug" (or both)

#### `has_all_of`
Contains all of these

```ruby
{field: 'tags', comparison: 'has_all_of', value: ['approved', 'reviewed']}
```

**Matches:** Records with BOTH "approved" AND "reviewed"

#### `is_exactly`
Contains exactly these (no more, no less)

```ruby
{field: 'tags', comparison: 'is_exactly', value: ['final', 'published']}
```

**Matches:** Records with ONLY "final" and "published" tags

#### `has_none_of`
Contains none of these

```ruby
{field: 'tags', comparison: 'has_none_of', value: ['archived', 'deleted']}
```

**Matches:** Records without "archived" or "deleted"

#### `is_empty`
No tags selected

```ruby
{field: 'tags', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has at least one tag

```ruby
{field: 'tags', comparison: 'is_not_empty', value: nil}
```

---

## Date Fields

**Field Types:** Date, Due Date, Date Range, First Created, Last Updated

### Operators

#### `is`
Exact date match

```ruby
{
  field: 'start_date',
  comparison: 'is',
  value: {date_mode: 'exact_date', date_mode_value: '2025-01-15'}
}
```

#### `is_not`
Not this date

```ruby
{
  field: 'event_date',
  comparison: 'is_not',
  value: {date_mode: 'exact_date', date_mode_value: '2025-12-25'}
}
```

#### `is_before`
Before this date

```ruby
{
  field: 'deadline',
  comparison: 'is_before',
  value: {date_mode: 'exact_date', date_mode_value: '2025-03-01'}
}
```

#### `is_on_or_before`
On or before this date

```ruby
{
  field: 'end_date',
  comparison: 'is_on_or_before',
  value: {date_mode: 'exact_date', date_mode_value: '2025-12-31'}
}
```

#### `is_after`
After this date (alias: `is_on_or_after`)

```ruby
{
  field: 'created_on',
  comparison: 'is_after',
  value: {date_mode: 'days_ago', date_mode_value: 30}
}
```

#### `is_overdue` (Due Date only)
Past the due date

```ruby
{field: 'due_date', comparison: 'is_overdue', value: nil}
```

#### `is_not_overdue` (Due Date only)
Not past the due date

```ruby
{field: 'due_date', comparison: 'is_not_overdue', value: nil}
```

#### `is_empty`
No date set

```ruby
{field: 'completion_date', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Date is set

```ruby
{field: 'start_date', comparison: 'is_not_empty', value: nil}
```

### Date Value Formats

#### Exact Date
```ruby
{
  date_mode: 'exact_date',
  date_mode_value: '2025-01-15'  # YYYY-MM-DD
}
```

#### Relative Dates
```ruby
# Today
{date_mode: 'today', date_mode_value: 0}

# 7 days from now
{date_mode: 'days_from_now', date_mode_value: 7}

# 30 days ago
{date_mode: 'days_ago', date_mode_value: 30}

# This week
{date_mode: 'this_week', date_mode_value: 0}

# This month
{date_mode: 'this_month', date_mode_value: 0}

# This year
{date_mode: 'this_year', date_mode_value: 0}
```

---

## Linked Record Fields

**Field Types:** Linked Record

### Operators

#### `contains`
Text search in linked record's display field

```ruby
{field: 'related_project', comparison: 'contains', value: 'Marketing'}
```

#### `not_contains`
Text doesn't appear in linked record

```ruby
{field: 'related_project', comparison: 'not_contains', value: 'Archived'}
```

#### `has_any_of`
Links to any of these records

```ruby
{
  field: 'related_project',
  comparison: 'has_any_of',
  value: ['rec_abc123', 'rec_def456']
}
```

**⚠️ Important:** Use record IDs, not labels!

#### `has_all_of`
Links to all of these records

```ruby
{
  field: 'dependencies',
  comparison: 'has_all_of',
  value: ['rec_task1', 'rec_task2']
}
```

#### `is_exactly`
Links to exactly these records (no more, no less)

```ruby
{
  field: 'team_members',
  comparison: 'is_exactly',
  value: ['rec_user1', 'rec_user2']
}
```

#### `has_none_of`
Doesn't link to any of these

```ruby
{
  field: 'related_project',
  comparison: 'has_none_of',
  value: ['rec_archived1', 'rec_archived2']
}
```

#### `is_empty`
No linked records

```ruby
{field: 'related_project', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has linked records

```ruby
{field: 'dependencies', comparison: 'is_not_empty', value: nil}
```

---

## User Assignment Fields

**Field Types:** Assigned To, Created By, Last Modified By, User

### Operators

#### `has_any_of`
Assigned to any of these users

```ruby
{
  field: 'assigned_to',
  comparison: 'has_any_of',
  value: ['user_john123', 'user_jane456']
}
```

#### `has_all_of`
Assigned to all of these users

```ruby
{
  field: 'reviewers',
  comparison: 'has_all_of',
  value: ['user_manager', 'user_lead']
}
```

#### `is_exactly`
Assigned to exactly these users

```ruby
{
  field: 'assigned_to',
  comparison: 'is_exactly',
  value: ['user_john123']
}
```

#### `has_none_of`
Not assigned to any of these users

```ruby
{
  field: 'assigned_to',
  comparison: 'has_none_of',
  value: ['user_inactive1', 'user_inactive2']
}
```

#### `is_empty`
Not assigned to anyone

```ruby
{field: 'assigned_to', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Assigned to someone

```ruby
{field: 'assigned_to', comparison: 'is_not_empty', value: nil}
```

---

## Yes/No (Boolean) Fields

**Field Types:** Yes/No, Checkbox

### Operators

#### `is`
Equals true or false

```ruby
# Checked
{field: 'is_active', comparison: 'is', value: true}

# Unchecked
{field: 'is_completed', comparison: 'is', value: false}
```

#### `is_empty`
No value set

```ruby
{field: 'confirmed', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has value (true or false)

```ruby
{field: 'verified', comparison: 'is_not_empty', value: nil}
```

---

## File & Image Fields

**Field Types:** Files, Images

### Operators

#### `file_name_contains`
Filename contains text

```ruby
{field: 'attachments', comparison: 'file_name_contains', value: 'invoice'}
```

#### `file_type_is`
File type matches

```ruby
{field: 'documents', comparison: 'file_type_is', value: 'pdf'}
```

**Valid file types:**
- `archive` - ZIP, RAR, 7Z, etc.
- `image` - JPG, PNG, GIF, SVG, etc.
- `music` - MP3, WAV, FLAC, etc.
- `pdf` - PDF documents
- `powerpoint` - PPT, PPTX
- `spreadsheet` - XLS, XLSX, CSV
- `video` - MP4, MOV, AVI, etc.
- `word` - DOC, DOCX
- `other` - Any other file type

#### `is_empty`
No files attached

```ruby
{field: 'attachments', comparison: 'is_empty', value: nil}
```

#### `is_not_empty`
Has files attached

```ruby
{field: 'documents', comparison: 'is_not_empty', value: nil}
```

---

## Formula & Lookup Fields

Formula and Lookup fields inherit operators from their return type:

- **Text formula** → Use Text operators
- **Number formula** → Use Number operators
- **Date formula** → Use Date operators
- **Boolean formula** → Use Boolean operators

**Example:**
```ruby
# If formula returns a number
{field: 'calculated_total', comparison: 'is_greater_than', value: 1000}

# If formula returns text
{field: 'full_name_formula', comparison: 'contains', value: 'Smith'}
```

---

## Empty Value Checks

All field types support checking for empty values:

```ruby
# Check if field is empty
{field: 'any_field', comparison: 'is_empty', value: nil}

# Check if field has a value
{field: 'any_field', comparison: 'is_not_empty', value: nil}
```

**Important:** Use `nil` or `null` as the value for empty checks.

---

## Common Operator Mistakes

### ❌ Using `is` with Linked Records
```ruby
# WRONG
{field: 'project', comparison: 'is', value: 'rec_abc123'}
```

### ✅ Use `has_any_of` instead
```ruby
# CORRECT
{field: 'project', comparison: 'has_any_of', value: ['rec_abc123']}
```

---

### ❌ Using Labels Instead of IDs
```ruby
# WRONG - using project name
{field: 'project', comparison: 'has_any_of', value: ['Marketing Campaign']}
```

### ✅ Use Record IDs
```ruby
# CORRECT - using record ID
{field: 'project', comparison: 'has_any_of', value: ['rec_abc123']}
```

---

### ❌ Wrong Date Format
```ruby
# WRONG
{field: 'start_date', comparison: 'is_after', value: '2025-01-15'}
```

### ✅ Use Date Object
```ruby
# CORRECT
{
  field: 'start_date',
  comparison: 'is_after',
  value: {date_mode: 'exact_date', date_mode_value: '2025-01-15'}
}
```

---

## Combining Operators

Use `operator: 'and'` or `operator: 'or'` to combine conditions:

### AND Logic (all must be true)
```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'}
  ]
}
```

### OR Logic (any can be true)
```ruby
{
  operator: 'or',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'status', comparison: 'is', value: 'Pending'}
  ]
}
```

### Nested Logic
```ruby
{
  operator: 'and',
  fields: [
    {
      operator: 'or',
      fields: [
        {field: 'priority', comparison: 'is', value: 'High'},
        {field: 'tags', comparison: 'has_any_of', value: ['urgent']}
      ]
    },
    {field: 'status', comparison: 'is', value: 'Active'}
  ]
}
```

---

## See Also

- **[Filtering Guide](../guides/filtering-guide.md)** - Complete filtering tutorial with examples
- **[Field Types Reference](field-types.md)** - SmartSuite to SQLite field type mapping
- **[User Guide](../guides/user-guide.md)** - General usage patterns
- **[API Reference: Records](../api/records.md)** - list_records documentation

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
