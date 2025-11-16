# Advanced Filtering Patterns

Complex filtering techniques and multi-criteria queries for SmartSuite MCP Server.

## Objective

Master advanced filtering to build sophisticated queries:
- Combine multiple conditions with AND/OR logic
- Filter by dates, numbers, text, and linked records
- Handle complex field types (multiple select, user assignments)
- Optimize filter performance
- Avoid common mistakes

**Time:** 20-30 minutes
**Level:** Intermediate
**Prerequisites:** Completed [Basic Workflow](basic-workflow.md) or familiar with fundamentals

---

## Part 1: Multi-Criteria Filtering (AND Logic)

### Example 1: Filter by Status AND Priority

**Scenario:** Find tasks that are Active AND High priority.

**Say to Claude:**
```
Show me tasks where status is "Active" AND priority is "High"
```

**Filter structure (what Claude builds):**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'}
  ]
}
```

**Expected response:**
```
=== RECORDS (8 of 127 total) ===

--- Record 1 of 8 ---
id: rec_001
title: Q4 Planning
status: Active
priority: High

--- Record 2 of 8 ---
id: rec_045
title: Security Audit
status: Active
priority: High

... (6 more records)
```

**What happened:**
- Both conditions must be true (AND logic)
- Cache query: `WHERE status = 'Active' AND priority = 'High'`
- **Performance:** ~10ms (cache hit)

---

### Example 2: Three-Condition Filter

**Scenario:** Find Active, High-priority tasks assigned to engineering team.

**Say to Claude:**
```
Show me Active tasks with High priority assigned to engineering team
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'priority', comparison: 'is', value: 'High'},
    {field: 'team', comparison: 'is', value: 'Engineering'}
  ]
}
```

**Result:** Only records matching ALL three conditions.

**💡 Tip:** More conditions = fewer results (narrower filter).

---

## Part 2: OR Logic

### Example 3: Filter by Multiple Statuses

**Scenario:** Find tasks that are either "Active" OR "In Progress".

**Say to Claude:**
```
Show me tasks where status is "Active" or "In Progress"
```

**Filter structure:**
```ruby
{
  operator: 'or',
  fields: [
    {field: 'status', comparison: 'is', value: 'Active'},
    {field: 'status', comparison: 'is', value: 'In Progress'}
  ]
}
```

**Alternative (more efficient):**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'status', comparison: 'is_any_of', value: ['Active', 'In Progress']}
  ]
}
```

**Expected response:**
```
=== RECORDS (45 of 127 total) ===

--- Record 1 of 45 ---
title: Q4 Planning
status: Active

--- Record 2 of 45 ---
title: Budget Review
status: In Progress

... (43 more records)
```

**💡 Tip:** Use `is_any_of` operator for cleaner OR logic on same field.

---

### Example 4: Cross-Field OR

**Scenario:** Find High-priority OR overdue tasks.

**Say to Claude:**
```
Show me tasks that are either High priority OR overdue
```

**Filter structure:**
```ruby
{
  operator: 'or',
  fields: [
    {field: 'priority', comparison: 'is', value: 'High'},
    {field: 'due_date', comparison: 'is_overdue', value: nil}
  ]
}
```

**Result:** Records matching EITHER condition (or both).

---

## Part 3: Nested Logic (AND + OR)

### Example 5: Complex Business Rule

**Scenario:** Find tasks that are:
- (High priority OR Critical priority) AND
- (Status is Active OR In Progress)

**Say to Claude:**
```
Show me tasks where priority is High or Critical, and status is Active or In Progress
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      operator: 'or',
      fields: [
        {field: 'priority', comparison: 'is', value: 'High'},
        {field: 'priority', comparison: 'is', value: 'Critical'}
      ]
    },
    {
      operator: 'or',
      fields: [
        {field: 'status', comparison: 'is', value: 'Active'},
        {field: 'status', comparison: 'is', value: 'In Progress'}
      ]
    }
  ]
}
```

**Equivalent (more efficient):**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'priority', comparison: 'is_any_of', value: ['High', 'Critical']},
    {field: 'status', comparison: 'is_any_of', value: ['Active', 'In Progress']}
  ]
}
```

**💡 Tip:** Use `is_any_of` to simplify OR conditions on same field.

---

## Part 4: Date Filtering

### Example 6: Date Range

**Scenario:** Find tasks due between Jan 15 and Jan 31, 2025.

**Say to Claude:**
```
Show me tasks due between January 15 and January 31, 2025
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'due_date',
      comparison: 'is_on_or_after',
      value: {
        date_mode: 'exact_date',
        date_mode_value: '2025-01-15'
      }
    },
    {
      field: 'due_date',
      comparison: 'is_on_or_before',
      value: {
        date_mode: 'exact_date',
        date_mode_value: '2025-01-31'
      }
    }
  ]
}
```

**Expected response:**
```
=== RECORDS (12 of 127 total) ===

--- Record 1 of 12 ---
title: Monthly Report
due_date: 2025-01-20

--- Record 2 of 12 ---
title: Team Sync
due_date: 2025-01-28

... (10 more records)
```

**💡 Tip:** Date filters require special object format with `date_mode` and `date_mode_value`.

---

### Example 7: Relative Dates

**Scenario:** Find tasks updated in the last 7 days.

**Say to Claude:**
```
Show me tasks updated in the last 7 days
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'updated_on',
      comparison: 'is_on_or_after',
      value: {
        date_mode: 'days_ago',
        date_mode_value: 7
      }
    }
  ]
}
```

**Date modes available:**
- `exact_date` - Specific date (YYYY-MM-DD)
- `days_ago` - X days in the past
- `days_from_now` - X days in the future
- `today`, `yesterday`, `tomorrow`
- `this_week`, `last_week`, `next_week`
- `this_month`, `last_month`, `next_month`

---

### Example 8: Overdue Tasks

**Scenario:** Find overdue tasks (past due date, not completed).

**Say to Claude:**
```
Show me overdue tasks
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'due_date', comparison: 'is_overdue', value: nil},
    {field: 'status', comparison: 'is_not', value: 'Completed'}
  ]
}
```

**💡 Tip:** Due Date fields have special `is_overdue` operator.

---

## Part 5: Numeric Filtering

### Example 9: Numeric Range

**Scenario:** Find projects with budget between $10,000 and $50,000.

**Say to Claude:**
```
Show me projects where budget is between 10000 and 50000
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'budget', comparison: 'is_equal_or_greater_than', value: 10000},
    {field: 'budget', comparison: 'is_equal_or_less_than', value: 50000}
  ]
}
```

**Numeric operators:**
- `is_equal_to`
- `is_not_equal_to`
- `is_greater_than`
- `is_less_than`
- `is_equal_or_greater_than`
- `is_equal_or_less_than`
- `is_empty`, `is_not_empty`

---

### Example 10: Comparison Filter

**Scenario:** Find tasks with more than 5 comments.

**Say to Claude:**
```
Show me tasks with more than 5 comments
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'comment_count', comparison: 'is_greater_than', value: 5}
  ]
}
```

---

## Part 6: Text Filtering

### Example 11: Text Contains

**Scenario:** Find customers whose name contains "Tech".

**Say to Claude:**
```
Show me customers where name contains "Tech"
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'company_name', comparison: 'contains', value: 'Tech'}
  ]
}
```

**Text operators:**
- `is` - Exact match
- `is_not` - Exact non-match
- `contains` - Substring match (case-insensitive)
- `not_contains` - No substring match
- `is_empty` - Field is empty/null
- `is_not_empty` - Field has value

**💡 Tip:** `contains` is case-insensitive, so "tech", "Tech", "TECH" all match.

---

### Example 12: Multiple Text Conditions

**Scenario:** Find emails from specific domains.

**Say to Claude:**
```
Show me contacts where email contains "@example.com" or "@demo.com"
```

**Filter structure:**
```ruby
{
  operator: 'or',
  fields: [
    {field: 'email', comparison: 'contains', value: '@example.com'},
    {field: 'email', comparison: 'contains', value: '@demo.com'}
  ]
}
```

---

## Part 7: Linked Record Filtering

### Example 13: Filter by Linked Record

**Scenario:** Find tasks linked to a specific project.

**Say to Claude:**
```
Show me tasks linked to project "Website Redesign"
```

**Filter structure (requires project record ID):**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'linked_project',
      comparison: 'has_any_of',
      value: ['rec_project_123']
    }
  ]
}
```

**Linked record operators:**
- `contains` - Has the linked record (single)
- `has_any_of` - Has any of these linked records (multiple)
- `has_all_of` - Has all of these linked records
- `is_exactly` - Has exactly these linked records (no more, no less)
- `has_none_of` - Doesn't have any of these
- `is_empty` - No linked records
- `is_not_empty` - Has at least one linked record

**⚠️ Common mistake:** Using `is` instead of `has_any_of` for linked records.

**❌ Wrong:**
```ruby
{field: 'linked_project', comparison: 'is', value: 'rec_project_123'}
```

**✅ Correct:**
```ruby
{field: 'linked_project', comparison: 'has_any_of', value: ['rec_project_123']}
```

---

### Example 14: Find Unlinked Records

**Scenario:** Find tasks not linked to any project.

**Say to Claude:**
```
Show me tasks that are not linked to any project
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'linked_project', comparison: 'is_empty', value: nil}
  ]
}
```

**💡 Tip:** Use `is_empty` with `nil` value for empty linked record checks.

---

## Part 8: Multiple Select / Tag Filtering

### Example 15: Has Any Tags

**Scenario:** Find tasks tagged with "urgent" or "bug".

**Say to Claude:**
```
Show me tasks tagged with "urgent" or "bug"
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'tags',
      comparison: 'has_any_of',
      value: ['urgent', 'bug']
    }
  ]
}
```

**Multiple select operators:**
- `has_any_of` - Has at least one of these values
- `has_all_of` - Has all of these values (and possibly more)
- `is_exactly` - Has exactly these values (no more, no less)
- `has_none_of` - Doesn't have any of these
- `is_empty` - No tags selected
- `is_not_empty` - Has at least one tag

---

### Example 16: Has All Tags

**Scenario:** Find tasks that must have both "customer-facing" AND "high-impact" tags.

**Say to Claude:**
```
Show me tasks tagged with both "customer-facing" and "high-impact"
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'tags',
      comparison: 'has_all_of',
      value: ['customer-facing', 'high-impact']
    }
  ]
}
```

**Result:** Only tasks with BOTH tags (may have additional tags too).

---

### Example 17: Exact Tag Match

**Scenario:** Find tasks with EXACTLY "bug" and "critical" tags (no other tags).

**Say to Claude:**
```
Show me tasks with exactly "bug" and "critical" tags, no others
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'tags',
      comparison: 'is_exactly',
      value: ['bug', 'critical']
    }
  ]
}
```

**Difference:**
- `has_all_of` - Must have these (can have more)
- `is_exactly` - Must have only these (no more, no less)

---

## Part 9: User Assignment Filtering

### Example 18: Filter by Assigned User

**Scenario:** Find tasks assigned to specific user.

**Say to Claude:**
```
Show me tasks assigned to john@example.com
```

**Filter structure (requires user ID):**
```ruby
{
  operator: 'and',
  fields: [
    {
      field: 'assigned_to',
      comparison: 'has_any_of',
      value: ['user_id_abc123']
    }
  ]
}
```

**Note:** User fields work like linked records - use `has_any_of` with user IDs.

**💡 Tip:** Use `search_member` tool to find user IDs by email/name first.

---

### Example 19: Find Unassigned Tasks

**Scenario:** Find tasks not assigned to anyone.

**Say to Claude:**
```
Show me unassigned tasks
```

**Filter structure:**
```ruby
{
  operator: 'and',
  fields: [
    {field: 'assigned_to', comparison: 'is_empty', value: nil}
  ]
}
```

---

## Part 10: Empty / Not Empty Checks

### Example 20: Find Records with Missing Data

**Scenario:** Find tasks missing description or due date.

**Say to Claude:**
```
Show me tasks where description is empty OR due date is empty
```

**Filter structure:**
```ruby
{
  operator: 'or',
  fields: [
    {field: 'description', comparison: 'is_empty', value: nil},
    {field: 'due_date', comparison: 'is_empty', value: nil}
  ]
}
```

**💡 Tip:** `is_empty` works for all field types - use `nil` as value.

---

## Part 11: Common Mistakes & Solutions

### Mistake 1: Wrong Operator for Field Type

**❌ Wrong:**
```ruby
# Using 'is' for linked record
{field: 'project', comparison: 'is', value: 'rec_123'}
```

**✅ Correct:**
```ruby
# Use 'has_any_of' for linked records
{field: 'project', comparison: 'has_any_of', value: ['rec_123']}
```

**Rule:** Check field type in table structure to choose correct operator.

---

### Mistake 2: Incorrect Date Format

**❌ Wrong:**
```ruby
{field: 'due_date', comparison: 'is', value: '2025-01-15'}
```

**✅ Correct:**
```ruby
{
  field: 'due_date',
  comparison: 'is',
  value: {
    date_mode: 'exact_date',
    date_mode_value: '2025-01-15'
  }
}
```

**Rule:** Date fields require object format with `date_mode`.

---

### Mistake 3: Confusing is_any_of vs has_any_of

**Single Select (use `is_any_of`):**
```ruby
{field: 'status', comparison: 'is_any_of', value: ['Active', 'Pending']}
```

**Multiple Select / Tags (use `has_any_of`):**
```ruby
{field: 'tags', comparison: 'has_any_of', value: ['urgent', 'bug']}
```

**Linked Records (use `has_any_of`):**
```ruby
{field: 'project', comparison: 'has_any_of', value: ['rec_123', 'rec_456']}
```

**Rule:**
- Single select → `is_any_of`
- Multiple select / Tags → `has_any_of`
- Linked records → `has_any_of`

---

### Mistake 4: Not Using Array for Multiple Values

**❌ Wrong:**
```ruby
{field: 'status', comparison: 'is_any_of', value: 'Active'}
```

**✅ Correct:**
```ruby
{field: 'status', comparison: 'is_any_of', value: ['Active']}
```

**Rule:** `is_any_of`, `has_any_of`, `has_all_of`, `is_exactly` require arrays.

---

## Part 12: Performance Optimization

### Tip 1: Filter Before Fetching

**❌ Inefficient:**
```
1. Show me all 10,000 tasks
2. [Manually scan for high-priority ones]
```

**✅ Efficient:**
```
Show me high-priority tasks
```

**Savings:** Only returns relevant records, saves tokens.

---

### Tip 2: Use Indexed Fields

**Faster:** Status, Priority, Assigned To (indexed in SmartSuite)
**Slower:** Long text fields, descriptions

**Tip:** Filter by status/priority first, then other criteria.

---

### Tip 3: Leverage Cache

**First query (cache miss):**
```
Show me Active tasks  →  1200ms, fetches ALL tasks
```

**Subsequent queries (cache hit):**
```
Show me High-priority tasks  →  10ms, queries cached data
Show me tasks by assignee     →  10ms, queries cached data
Show me overdue tasks          →  10ms, queries cached data
```

**Result:** 1 API call, unlimited filtered queries for 4 hours.

---

## Summary

### Filter Operators by Field Type

**Text fields:**
- `is`, `is_not`, `contains`, `not_contains`, `is_empty`, `is_not_empty`

**Single select:**
- `is`, `is_not`, `is_any_of`, `is_none_of`, `is_empty`, `is_not_empty`

**Multiple select / Tags:**
- `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`

**Numeric:**
- `is_equal_to`, `is_not_equal_to`, `is_greater_than`, `is_less_than`, `is_equal_or_greater_than`, `is_equal_or_less_than`, `is_empty`, `is_not_empty`

**Date:**
- `is`, `is_not`, `is_before`, `is_on_or_before`, `is_after`, `is_on_or_after`, `is_overdue`, `is_empty`, `is_not_empty`

**Linked records:**
- `contains`, `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`

**User assignments:**
- `has_any_of`, `has_all_of`, `is_exactly`, `has_none_of`, `is_empty`, `is_not_empty`

---

### Key Takeaways

1. **Use correct operator for field type** - Check table structure
2. **Date filters need special format** - `date_mode` object
3. **Linked records use has_any_of** - Not `is`
4. **Multiple values require arrays** - `['value1', 'value2']`
5. **Empty checks use nil** - `{comparison: 'is_empty', value: nil}`
6. **Cache enables unlimited filtering** - Query once, filter many times
7. **Filter early for performance** - Narrow results at database level

---

## Next Steps

**Master filtering:**
- **[Filtering Guide](../guides/filtering-guide.md)** - Complete operator reference
- **[Performance Guide](../guides/performance-guide.md)** - Optimization strategies
- **[User Guide](../guides/user-guide.md)** - General usage patterns

**Practice:**
1. Build a 3-condition AND filter
2. Create an OR filter across different fields
3. Filter by date range
4. Find empty/unassigned records
5. Combine AND + OR logic

---

Congratulations! You now have advanced filtering skills and can build sophisticated queries to find exactly the data you need.
