# View Operations

Complete reference for SmartSuite view (report) operations.

## Overview

Views (also called "reports" in the API) are saved configurations that control how records are displayed, filtered, sorted, and grouped in SmartSuite. They provide different perspectives on your data.

**Key Features:**
- Get records from specific views (with view's filters applied)
- Create new views with custom configurations
- Support all view types (grid, calendar, kanban, map, etc.)
- Automatic filter and sort application

---

## get_view_records

Get records from a view with the view's filters, sorting, and field visibility applied.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `view_id` | string | ✅ Yes | View identifier |
| `with_empty_values` | boolean | No | Include empty field values (default: false) |

### Example

```ruby
get_view_records(
  table_id: 'tbl_6796989a7ee3c6b731717836',
  view_id: 'view_active_tasks'
)
```

### Response Format

Default TOON format:

```
15 of 15 filtered (15 total)
records[15]{id|title|status|priority|assigned_to}:
rec_123abc|Q4 Planning|Active|High|John Doe
rec_456def|Budget Review|Active|Medium|Jane Smith
rec_789ghi|Team Sync|Active|Low|Bob Wilson
[... etc]
```

Use `format: "json"` for JSON output if needed.

### View Configuration Applied

When you fetch records from a view, SmartSuite automatically applies:

**1. Filters** - Only records matching view's filter criteria
```ruby
# View configured with: status = "Active"
# Returns only active records
```

**2. Sorting** - Records sorted per view configuration
```ruby
# View configured with: sort by priority DESC, then created_on ASC
# Records returned in that order
```

**3. Grouping** - Records grouped if view has grouping
```ruby
# View configured with: group by status
# Records organized by status groups
```

**4. Field Visibility** - Only visible fields included
```ruby
# View configured to show: title, status, priority
# Other fields excluded from response
```

### View Types

SmartSuite supports multiple view types, all accessible via this endpoint:

- **Grid** - Traditional table view
- **Calendar** - Date-based calendar view
- **Kanban** - Card-based board view
- **Map** - Geographic map view
- **Gallery** - Image/card gallery view
- **Timeline** - Gantt-style timeline
- **Chart** - Data visualization

### Use Cases

**1. Get Pre-Filtered Data:**
```ruby
# Instead of complex filters, use existing view
get_view_records(
  table_id: 'tbl_tasks',
  view_id: 'view_my_active_tasks'
)
# Returns only your active tasks (per view config)
```

**2. Consistent Data Display:**
```ruby
# Use same view config as SmartSuite UI
get_view_records(
  table_id: 'tbl_projects',
  view_id: 'view_current_projects'
)
# Same sorting, filtering, fields as UI view
```

**3. Department-Specific Views:**
```ruby
# Sales view
get_view_records(
  table_id: 'tbl_customers',
  view_id: 'view_sales_pipeline'
)

# Support view (different filters/fields)
get_view_records(
  table_id: 'tbl_customers',
  view_id: 'view_support_tickets'
)
```

**4. Calendar View Data:**
```ruby
# Get calendar-formatted events
get_view_records(
  table_id: 'tbl_events',
  view_id: 'view_event_calendar'
)
# Returns events with date formatting per calendar view
```

### With Empty Values

```ruby
# Include empty field values in response
get_view_records(
  table_id: 'tbl_abc123',
  view_id: 'view_xyz789',
  with_empty_values: true
)
```

By default, empty values are excluded to reduce response size. Set to `true` to include fields with null/empty values.

### Notes

- **No cache** - always fetches from API
- **View config applied** - filters, sorting, grouping, field visibility
- **Same as UI** - identical to viewing in SmartSuite interface
- **Use for consistency** - reuse existing view configurations

---

## create_view

Create a new view (report) in a table.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `application` | string | ✅ Yes | Table ID where view will be created |
| `solution` | string | ✅ Yes | Solution ID containing the table |
| `label` | string | ✅ Yes | View display name |
| `view_mode` | string | ✅ Yes | View type (grid, calendar, kanban, etc.) |
| `state` | object | No | View configuration (filters, sort, grouping) |
| `description` | string | No | View description |
| `is_private` | boolean | No | Private view (default: false) |
| `is_locked` | boolean | No | Locked view (default: false) |
| `order` | integer | No | Display position in view list |

### Basic Example

```ruby
create_view(
  application: 'tbl_6796989a7ee3c6b731717836',
  solution: 'sol_abc123def456',
  label: 'Active Tasks',
  view_mode: 'grid'
)
```

### With Filters and Sorting

```ruby
create_view(
  application: 'tbl_tasks',
  solution: 'sol_projects',
  label: 'My High Priority Tasks',
  view_mode: 'grid',
  description: 'Shows my active high-priority tasks',
  state: {
    filter: {
      operator: 'and',
      fields: [
        {
          field: 'status',
          comparison: 'is',
          value: 'Active'
        },
        {
          field: 'priority',
          comparison: 'is',
          value: 'High'
        },
        {
          field: 'assigned_to',
          comparison: 'has_any_of',
          value: ['user_current']
        }
      ]
    },
    sort: [
      {
        field: 'due_date',
        direction: 'asc'
      }
    ],
    fields: ['title', 'status', 'priority', 'due_date', 'assigned_to']
  }
)
```

### View Types

**Grid View** (traditional table):
```ruby
create_view(
  application: 'tbl_abc123',
  solution: 'sol_xyz789',
  label: 'All Records',
  view_mode: 'grid'
)
```

**Calendar View** (date-based):
```ruby
create_view(
  application: 'tbl_events',
  solution: 'sol_calendar',
  label: 'Event Calendar',
  view_mode: 'calendar',
  state: {
    calendar_field: 'event_date',  # Field to use for dates
    fields: ['title', 'event_date', 'location']
  }
)
```

**Kanban View** (card board):
```ruby
create_view(
  application: 'tbl_tasks',
  solution: 'sol_projects',
  label: 'Task Board',
  view_mode: 'kanban',
  state: {
    group: {
      field: 'status',  # Group by status
      sort: 'asc'
    },
    fields: ['title', 'status', 'assigned_to', 'priority']
  }
)
```

**Map View** (geographic):
```ruby
create_view(
  application: 'tbl_locations',
  solution: 'sol_geo',
  label: 'Location Map',
  view_mode: 'map',
  map_state: {
    center: {lat: 37.7749, lng: -122.4194},
    zoom: 10
  },
  state: {
    fields: ['name', 'address', 'coordinates']
  }
)
```

**Timeline View** (Gantt):
```ruby
create_view(
  application: 'tbl_projects',
  solution: 'sol_pm',
  label: 'Project Timeline',
  view_mode: 'timeline',
  state: {
    start_date_field: 'start_date',
    end_date_field: 'due_date',
    group: {field: 'department'},
    fields: ['title', 'start_date', 'due_date', 'owner']
  }
)
```

### View State Configuration

The `state` object configures view behavior:

**Filter:**
```ruby
state: {
  filter: {
    operator: 'and',
    fields: [
      {field: 'status', comparison: 'is', value: 'Active'}
    ]
  }
}
```

**Sort:**
```ruby
state: {
  sort: [
    {field: 'priority', direction: 'desc'},
    {field: 'created_on', direction: 'asc'}
  ]
}
```

**Group:**
```ruby
state: {
  group: {
    field: 'department',
    sort: 'asc'
  }
}
```

**Visible Fields:**
```ruby
state: {
  fields: ['title', 'status', 'priority']  # Only these fields visible
}
```

### Privacy and Permissions

**Private View:**
```ruby
create_view(
  application: 'tbl_abc123',
  solution: 'sol_xyz789',
  label: 'My Private View',
  view_mode: 'grid',
  is_private: true  # Only visible to creator
)
```

**Locked View:**
```ruby
create_view(
  application: 'tbl_abc123',
  solution: 'sol_xyz789',
  label: 'Official Report',
  view_mode: 'grid',
  is_locked: true  # Cannot be modified by others
)
```

### Response Format

Returns the created view:

```
=== VIEW CREATED ===

id: view_new123abc
label: Active Tasks
view_mode: grid
table: tbl_6796989a7ee3c6b731717836
solution: sol_abc123def456
is_private: false
is_locked: false

View successfully created!
```

### Notes

- **No cache** - direct API operation
- **Complex configurations** - supports all SmartSuite view features
- **Reusable** - create views programmatically for consistency
- **Use view IDs** from response in `get_view_records`

---

## Common Patterns

### Create Standard Views for New Table

```ruby
# 1. Create table
create_table(
  solution_id: 'sol_projects',
  name: 'Tasks',
  structure: [...]
)
# Returns: {id: 'tbl_new123'}

# 2. Create "All Tasks" view
create_view(
  application: 'tbl_new123',
  solution: 'sol_projects',
  label: 'All Tasks',
  view_mode: 'grid'
)

# 3. Create "My Tasks" view
create_view(
  application: 'tbl_new123',
  solution: 'sol_projects',
  label: 'My Tasks',
  view_mode: 'grid',
  state: {
    filter: {
      operator: 'and',
      fields: [{
        field: 'assigned_to',
        comparison: 'has_any_of',
        value: ['user_current']
      }]
    }
  }
)

# 4. Create "Kanban Board" view
create_view(
  application: 'tbl_new123',
  solution: 'sol_projects',
  label: 'Task Board',
  view_mode: 'kanban',
  state: {
    group: {field: 'status'}
  }
)
```

### Use View for Consistent Filtering

```ruby
# Instead of repeating complex filters
# Create a view once:
create_view(
  application: 'tbl_tasks',
  solution: 'sol_pm',
  label: 'Critical Overdue',
  view_mode: 'grid',
  state: {
    filter: {
      operator: 'and',
      fields: [
        {field: 'priority', comparison: 'is', value: 'Critical'},
        {field: 'due_date', comparison: 'is_before', value: {
          date_mode: 'today',
          date_mode_value: 0
        }},
        {field: 'status', comparison: 'is_not', value: 'Completed'}
      ]
    },
    sort: [{field: 'due_date', direction: 'asc'}]
  }
)

# Then use it repeatedly:
get_view_records(
  table_id: 'tbl_tasks',
  view_id: 'view_critical_overdue'
)
```

### Create Department Views

```ruby
# Sales view
create_view(
  application: 'tbl_customers',
  solution: 'sol_crm',
  label: 'Sales Pipeline',
  view_mode: 'kanban',
  state: {
    group: {field: 'sales_stage'},
    filter: {
      operator: 'and',
      fields: [{
        field: 'assigned_team',
        comparison: 'is',
        value: 'team_sales'
      }]
    }
  }
)

# Support view
create_view(
  application: 'tbl_customers',
  solution: 'sol_crm',
  label: 'Support Tickets',
  view_mode: 'grid',
  state: {
    filter: {
      operator: 'and',
      fields: [{
        field: 'has_open_ticket',
        comparison: 'is',
        value: true
      }]
    },
    sort: [{field: 'ticket_priority', direction: 'desc'}]
  }
)
```

---

## Best Practices

### 1. Create Views for Common Queries

**✅ Good:**
```ruby
# Create views for frequent queries
create_view(
  application: 'tbl_tasks',
  solution: 'sol_pm',
  label: 'Overdue Tasks',
  view_mode: 'grid',
  state: {
    filter: {...}  # Complex overdue logic
  }
)

# Use view instead of repeating filters
get_view_records(table_id: 'tbl_tasks', view_id: 'view_overdue')
```

**❌ Avoid:**
```ruby
# Repeating complex filters every time
list_records('tbl_tasks', 100, 0,
  fields: [...],
  filter: {...very complex filter...}
)
```

### 2. Use Descriptive View Names

**✅ Good:**
```ruby
create_view(
  label: 'Q4 2025 Projects - Engineering Team',
  ...
)
```

**❌ Avoid:**
```ruby
create_view(
  label: 'View 1',  # Not descriptive
  ...
)
```

### 3. Set Appropriate Privacy

**✅ Good:**
```ruby
# Public view for team use
create_view(
  label: 'Team Dashboard',
  is_private: false
)

# Private view for personal use
create_view(
  label: 'My Personal Tasks',
  is_private: true
)
```

**❌ Avoid:**
```ruby
# Everything private (limits collaboration)
create_view(
  label: 'Team Dashboard',
  is_private: true  # Team can't access
)
```

### 4. Include Field Configuration

**✅ Good:**
```ruby
create_view(
  label: 'Active Tasks',
  state: {
    fields: ['title', 'status', 'priority'],  # Specific fields
    filter: {...},
    sort: [...]
  }
)
```

**❌ Avoid:**
```ruby
create_view(
  label: 'Active Tasks',
  state: {
    filter: {...}  # No field configuration
  }
)
# All fields shown (may be too many)
```

---

## Error Handling

### Table Not Found

```
Error: Table not found: tbl_xyz123
```

**Solution:** Verify table ID with `list_tables`

### Solution Not Found

```
Error: Solution not found: sol_xyz123
```

**Solution:** Verify solution ID with `list_solutions`

### View Not Found

```
Error: View not found: view_xyz123
```

**Solution:**
- View may be deleted
- View may be private (not accessible to you)
- Verify view exists in table

### Invalid View Mode

```
Error: Invalid view_mode: invalidmode
```

**Solution:** Use valid view type (grid, calendar, kanban, map, gallery, timeline, gantt)

---

## Related Documentation

- **[Record Operations](records.md)** - Work with records
- **[Filtering Guide](../guides/filtering-guide.md)** - Master filter syntax
- **[User Guide](../guides/user-guide.md)** - View usage patterns
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
