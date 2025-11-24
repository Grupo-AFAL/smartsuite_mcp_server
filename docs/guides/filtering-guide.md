# Filtering Guide

Master advanced filtering techniques for SmartSuite queries.

## Overview

Filtering is the most powerful way to narrow down records and find exactly what you need. This guide covers SmartSuite's filter syntax, operators for different field types, and practical examples.

**What you'll learn:**
- Filter syntax structure
- Operators by field type
- Combining multiple conditions
- Date filtering
- Linked record filtering
- Common patterns and pitfalls

---

## Filter Basics

### Filter Structure

All SmartSuite filters follow this structure:

```ruby
{
  operator: 'and',  # or 'or'
  fields: [
    {
      field: 'field_slug',
      comparison: 'operator',
      value: 'value'
    }
  ]
}
```

### Simple Example

**Natural language:**
```
Show me active tasks
```

**Claude translates to:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'status',
      comparison: 'is',
      value: 'Active'
    }
  ]
}
```

---

## Combining Conditions

### AND Logic

All conditions must be true:

```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'}
  ]
}
```

**Matches:** Records where status IS Active AND priority IS High

### OR Logic

Any condition can be true:

```ruby
{
  operator: 'or',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'status', comparison: 'is', value: 'Pending'}
  ]
}
```

**Matches:** Records where status IS Active OR status IS Pending

### Nested Logic

Combine AND/OR for complex queries:

```ruby
{
  operator: 'and',
  fields: [
    # High priority OR urgent tag
    {
      operator: 'or',
      fields: [
        {field: 'priority', comparison: 'is', value: 'High'},
        {field: 'tags', comparison: 'has_any_of', value: ['urgent']}
      ]
    },
    # AND status is active
    {field: 'status', comparison: 'is', value: 'Active'}
  ]
}
```

**Matches:** (High priority OR urgent tag) AND Active

---

## Operators by Field Type

### Text Fields

**Field types:** Text, Email, Phone, Full Name, Address, Link, Text Area

**Operators:**
- `is` - Exact match
- `is_not` - Not equal
- `contains` - Contains substring
- `not_contains` - Doesn't contain substring
- `is_empty` - Field is empty
- `is_not_empty` - Field has value

**Examples:**

```ruby
# Email contains "example.com"
{field: 'email', comparison: 'contains', value: 'example.com'}

# Name is not empty
{field: 'full_name', comparison: 'is_not_empty', value: nil}

# Phone is exactly this number
{field: 'phone', comparison: 'is', value: '+1-555-0100'}
```

### Number Fields

**Field types:** Number, Currency, Rating, Percent, Duration

**Operators:**
- `is_equal_to` - Equals
- `is_not_equal_to` - Not equals
- `is_greater_than` - Greater than
- `is_less_than` - Less than
- `is_equal_or_greater_than` - Greater than or equal
- `is_equal_or_less_than` - Less than or equal
- `is_empty` - Field is empty
- `is_not_empty` - Field has value

**Examples:**

```ruby
# Budget greater than $10,000
{field: 'budget', comparison: 'is_greater_than', value: 10000}

# Priority between 3 and 5 (inclusive)
{
  operator: 'and',
  fields: [
    {field: 'priority', comparison: 'is_equal_or_greater_than', value: 3},
    {field: 'priority', comparison: 'is_equal_or_less_than', value: 5}
  ]
}

# Rating is not empty
{field: 'rating', comparison: 'is_not_empty', value: nil}
```

### Single Select / Status

**Field types:** Single Select, Status

**Operators:**
- `is` - Equals option
- `is_not` - Not equals option
- `is_any_of` - Matches any in list
- `is_none_of` - Matches none in list
- `is_empty` - No selection
- `is_not_empty` - Has selection

**Examples:**

```ruby
# Status is Active
{field: 'status', comparison: 'is', value: 'Active'}

# Status is Active OR Pending
{field: 'status', comparison: 'is_any_of', value: ['Active', 'Pending']}

# Status is not Cancelled or Completed
{field: 'status', comparison: 'is_none_of', value: ['Cancelled', 'Completed']}

# Department not selected
{field: 'department', comparison: 'is_empty', value: nil}
```

### Multiple Select / Tags

**Field types:** Multiple Select, Tags

**Operators:**
- `has_any_of` - Contains at least one
- `has_all_of` - Contains all specified
- `is_exactly` - Contains exactly these (no more, no less)
- `has_none_of` - Contains none of these
- `is_empty` - No tags selected
- `is_not_empty` - Has at least one tag

**Examples:**

```ruby
# Has "urgent" OR "bug" tag
{field: 'tags', comparison: 'has_any_of', value: ['urgent', 'bug']}

# Has BOTH "approved" AND "reviewed" tags
{field: 'tags', comparison: 'has_all_of', value: ['approved', 'reviewed']}

# Has ONLY "final" and "approved" (no other tags)
{field: 'tags', comparison: 'is_exactly', value: ['final', 'approved']}

# Doesn't have "archived" or "deleted"
{field: 'tags', comparison: 'has_none_of', value: ['archived', 'deleted']}
```

### Date Fields

**Field types:** Date, Due Date, Date Range, First Created, Last Updated

**Operators:**
- `is` - Exact date
- `is_not` - Not this date
- `is_before` - Before date
- `is_on_or_before` - On or before date
- `is_after` - After date (alias: `is_on_or_after`)
- `is_empty` - No date set
- `is_not_empty` - Date is set

**Special for Due Date:**
- `is_overdue` - Past due date
- `is_not_overdue` - Not past due date

**Date Value Format:**

```ruby
{
  date_mode: 'exact_date',
  date_mode_value: '2025-01-15'  # YYYY-MM-DD
}
```

**Or relative dates:**

```ruby
# Today
{date_mode: 'today', date_mode_value: 0}

# 7 days from now
{date_mode: 'days_from_now', date_mode_value: 7}

# 30 days ago
{date_mode: 'days_ago', date_mode_value: 30}
```

**Examples:**

```ruby
# Due date is after January 1, 2025
{
  field: 'due_date',
  comparison: 'is_after',
  value: {
    date_mode: 'exact_date',
    date_mode_value: '2025-01-01'
  }
}

# Created in last 7 days
{
  field: 'created_on',
  comparison: 'is_on_or_after',
  value: {
    date_mode: 'days_ago',
    date_mode_value: 7
  }
}

# Tasks that are overdue
{field: 'due_date', comparison: 'is_overdue', value: nil}

# Date range: January 2025
{
  operator: 'and',
  fields: [
    {
      field: 'event_date',
      comparison: 'is_on_or_after',
      value: {date_mode: 'exact_date', date_mode_value: '2025-01-01'}
    },
    {
      field: 'event_date',
      comparison: 'is_on_or_before',
      value: {date_mode: 'exact_date', date_mode_value: '2025-01-31'}
    }
  ]
}
```

### Linked Record Fields

**Field types:** Linked Record

**Operators:**
- `contains` - Text search in linked record
- `not_contains` - Text doesn't appear in linked
- `has_any_of` - Links to any of these records
- `has_all_of` - Links to all of these records
- `is_exactly` - Links to exactly these records
- `has_none_of` - Doesn't link to any of these
- `is_empty` - No linked records
- `is_not_empty` - Has linked records

**⚠️ Important:** Use record IDs, not labels!

**Examples:**

```ruby
# Links to specific project
{
  field: 'related_project',
  comparison: 'has_any_of',
  value: ['rec_project123']
}

# Links to Project A OR Project B
{
  field: 'related_project',
  comparison: 'has_any_of',
  value: ['rec_projectA', 'rec_projectB']
}

# No linked records
{
  field: 'related_project',
  comparison: 'is_empty',
  value: nil
}

# Has ANY linked records
{
  field: 'related_project',
  comparison: 'is_not_empty',
  value: nil
}
```

**Common mistake:**
```ruby
# ❌ WRONG - using label
{field: 'related_project', comparison: 'is', value: 'Project Name'}

# ✅ CORRECT - using record ID
{field: 'related_project', comparison: 'has_any_of', value: ['rec_abc123']}
```

### User Assignment Fields

**Field types:** Assigned To, Created By, Last Modified By

**Operators:**
- `has_any_of` - Assigned to any of these users
- `has_all_of` - Assigned to all of these users
- `is_exactly` - Assigned to exactly these users
- `has_none_of` - Not assigned to any of these users
- `is_empty` - Not assigned to anyone
- `is_not_empty` - Assigned to someone

**Examples:**

```ruby
# Assigned to John
{
  field: 'assigned_to',
  comparison: 'has_any_of',
  value: ['user_john123']
}

# Assigned to John OR Jane
{
  field: 'assigned_to',
  comparison: 'has_any_of',
  value: ['user_john123', 'user_jane456']
}

# Not assigned to anyone
{
  field: 'assigned_to',
  comparison: 'is_empty',
  value: nil
}

# Assigned to someone
{
  field: 'assigned_to',
  comparison: 'is_not_empty',
  value: nil
}
```

### Yes/No (Boolean) Fields

**Field types:** Yes/No, Checkbox

**Operators:**
- `is` - Equals true/false
- `is_empty` - No value set
- `is_not_empty` - Has value

**Examples:**

```ruby
# Is active (checked)
{field: 'is_active', comparison: 'is', value: true}

# Is not completed (unchecked)
{field: 'is_completed', comparison: 'is', value: false}
```

### File & Image Fields

**Field types:** Files, Images

**Operators:**
- `file_name_contains` - Filename contains text
- `file_type_is` - File type matches
- `is_empty` - No files attached
- `is_not_empty` - Has files

**Valid file types:**
- `archive` (zip, rar, etc.)
- `image` (jpg, png, gif, etc.)
- `music` (mp3, wav, etc.)
- `pdf`
- `powerpoint` (ppt, pptx)
- `spreadsheet` (xls, xlsx, csv)
- `video` (mp4, mov, etc.)
- `word` (doc, docx)
- `other`

**Examples:**

```ruby
# Has PDF attachment
{field: 'attachments', comparison: 'file_type_is', value: 'pdf'}

# Filename contains "invoice"
{field: 'attachments', comparison: 'file_name_contains', value: 'invoice'}

# Has any attachments
{field: 'attachments', comparison: 'is_not_empty', value: nil}
```

---

## Common Patterns

### Find Overdue High-Priority Tasks

```ruby
{
  operator: 'and',
  fields: [
    {field: 'priority', comparison: 'is', value: 'High'},
    {field: 'due_date', comparison: 'is_overdue', value: nil},
    {field: 'status', comparison: 'is_not', value: 'Completed'}
  ]
}
```

### Find Records Updated This Week

```ruby
{
  field: 'last_updated',
  comparison: 'is_on_or_after',
  value: {
    date_mode: 'days_ago',
    date_mode_value: 7
  }
}
```

### Find Unassigned Tasks

```ruby
{
  operator: 'and',
  fields: [
    {field: 'assigned_to', comparison: 'is_empty', value: nil},
    {field: 'status', comparison: 'is_not', value: 'Completed'}
  ]
}
```

### Find My High-Priority Tasks

```ruby
{
  operator: 'and',
  fields: [
    {field: 'assigned_to', comparison: 'has_any_of', value: ['user_me']},
    {field: 'priority', comparison: 'is_any_of', value: ['High', 'Critical']},
    {field: 'status', comparison: 'is', value: 'Active'}
  ]
}
```

### Find Records with Specific Tag AND Status

```ruby
{
  operator: 'and',
  fields: [
    {field: 'tags', comparison: 'has_any_of', value: ['urgent']},
    {field: 'status', comparison: 'is', value: 'Active'}
  ]
}
```

### Find Records in Budget Range

```ruby
{
  operator: 'and',
  fields: [
    {field: 'budget', comparison: 'is_equal_or_greater_than', value: 10000},
    {field: 'budget', comparison: 'is_equal_or_less_than', value: 50000}
  ]
}
```

### Find Records Missing Required Data

```ruby
{
  operator: 'or',
  fields: [
    {field: 'customer_email', comparison: 'is_empty', value: nil},
    {field: 'contact_phone', comparison: 'is_empty', value: nil}
  ]
}
```

---

## Natural Language Filtering

You don't need to write filter syntax manually. Just ask Claude naturally:

**Instead of writing:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'}
  ]
}
```

**Just ask:**
```
Show me active high-priority tasks
```

Claude will construct the filter automatically.

### Examples

**Simple:**
```
Show me completed tasks
```

**With dates:**
```
Show me tasks created in the last week
```

**With assignments:**
```
Show me tasks assigned to john@example.com
```

**Complex:**
```
Show me high or critical priority tasks that are active and assigned to the engineering team
```

**With ranges:**
```
Show me projects with budget between $10K and $50K
```

---

## Common Mistakes

### 1. Wrong Operator for Field Type

**❌ Wrong:**
```ruby
# Single select with has_any_of (wrong for single select)
{field: 'status', comparison: 'has_any_of', value: ['Active']}
```

**✅ Correct:**
```ruby
{field: 'status', comparison: 'is', value: 'Active'}
# Or for multiple options:
{field: 'status', comparison: 'is_any_of', value: ['Active', 'Pending']}
```

### 2. Using Labels Instead of IDs

**❌ Wrong:**
```ruby
# Linked record with label
{field: 'project', comparison: 'is', value: 'Project Alpha'}
```

**✅ Correct:**
```ruby
# Linked record with ID
{field: 'project', comparison: 'has_any_of', value: ['rec_abc123']}
```

### 3. Wrong Date Format

**❌ Wrong:**
```ruby
{field: 'due_date', comparison: 'is_after', value: '01/15/2025'}
```

**✅ Correct:**
```ruby
{
  field: 'due_date',
  comparison: 'is_after',
  value: {
    date_mode: 'exact_date',
    date_mode_value: '2025-01-15'  # YYYY-MM-DD
  }
}
```

### 4. Mixing up is vs has_any_of

**For single select:**
```ruby
✅ {field: 'status', comparison: 'is', value: 'Active'}
❌ {field: 'status', comparison: 'has_any_of', value: ['Active']}
```

**For multiple select:**
```ruby
✅ {field: 'tags', comparison: 'has_any_of', value: ['urgent']}
❌ {field: 'tags', comparison: 'is', value: 'urgent'}
```

**For linked records:**
```ruby
✅ {field: 'project', comparison: 'has_any_of', value: ['rec_123']}
❌ {field: 'project', comparison: 'is', value: 'rec_123'}
```

---

## Cache vs API Filtering

**Important:** When using cache (default), SmartSuite API filters are ignored. All filtering happens via SQL on cached data.

**Cache enabled (default):**
```ruby
# Filter applied locally on cached records
list_records('tbl_123', 10, 0,
  fields: ['status'],
  filter: {...}  # Applied via SQL
)
```

**After refreshing cache:**
```ruby
# Invalidate cache first if you need fresh data
refresh_cache('records', table_id: 'tbl_123')

# Then query - filter applied locally on fresh cached records
list_records('tbl_123', 10, 0,
  fields: ['status'],
  filter: {...}
)
```

Cache is fast and uses fewer API calls. Use `refresh_cache` when you need guaranteed fresh data.

---

## Debugging Filters

### Check Your Filter

Ask Claude to explain:
```
Why am I getting no results for this filter?
```

Claude will review:
- Filter syntax
- Field types
- Operator compatibility
- Value formats

### Test Incrementally

**Start simple:**
```
Show me ALL tasks (no filter)
```

**Add one condition:**
```
Show me tasks where status is Active
```

**Add another:**
```
Show me Active tasks with High priority
```

This helps isolate which condition is causing issues.

### Verify Field Values

```
What are the possible values for the "status" field?
```

Claude will get the field structure and show you valid options.

---

## Related Documentation

- **[API Reference: Records](../api/records.md)** - list_records with filtering
- **[Filter Operators Reference](../reference/filter-operators.md)** - Complete operator list
- **[Field Types Reference](../reference/field-types.md)** - All field types
- **[User Guide](user-guide.md)** - General usage patterns
- **[Performance Guide](performance-guide.md)** - Optimize filtering

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
