# Workspace Operations

Complete reference for SmartSuite workspace (solution) operations.

## Overview

Solutions are the top-level containers in SmartSuite - they're your workspaces that contain tables (applications), members, and data. The server provides comprehensive solution management tools.

**Key Features:**
- List all accessible solutions
- Filter solutions by owner
- Analyze solution usage and activity
- Track most recent data updates
- Cache-first strategy (4-hour TTL)

---

## list_solutions

List all solutions (workspaces) accessible to your account.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fields` | array | No | Field names to return (client-side filtered) |
| `include_activity_data` | boolean | No | Include usage/activity metrics (default: false) |

### Basic Example

```ruby
# List all solutions with essential fields
list_solutions
```

### Response Format

```
=== SOLUTIONS (5 total) ===

--- Solution 1 of 5 ---
id: sol_123abc456def
name: Customer Management
logo_icon: users
logo_color: blue

--- Solution 2 of 5 ---
id: sol_789ghi012jkl
name: Project Tracking
logo_icon: briefcase
logo_color: green

[... etc]
```

### With Specific Fields

```ruby
# Request specific fields
list_solutions(fields: ['id', 'name', 'status', 'members_count'])
```

**Note:** The SmartSuite API doesn't support field filtering - the server applies client-side filtering after fetching all data.

### With Activity Data

```ruby
# Include usage metrics
list_solutions(include_activity_data: true)
```

Returns additional fields:
- `status` - Solution status
- `last_access` - Last access timestamp
- `records_count` - Total records across all tables
- `members_count` - Number of members
- `applications_count` - Number of tables
- `automation_count` - Number of automations
- `has_demo_data` - Whether solution contains demo data

### Available Fields

**Essential fields** (returned by default):
- `id` - Solution identifier
- `name` - Solution name
- `logo_icon` - Icon name
- `logo_color` - Icon color

**Activity fields** (with `include_activity_data: true`):
- `status` - Active status
- `last_access` - Last access date
- `records_count` - Total records
- `members_count` - Member count
- `applications_count` - Table count
- `automation_count` - Automation count
- `has_demo_data` - Demo data flag

**Metadata fields** (available with `fields` parameter):
- `slug` - URL-friendly identifier
- `description` - Solution description
- `created` - Creation timestamp
- `created_by` - Creator user ID
- `updated` - Last update timestamp
- `updated_by` - Last updater user ID
- `permissions` - Permissions object (⚠️ large)
- `hidden` - Hidden flag
- `sharing_enabled` - Sharing status
- `sharing_hash` - Share link hash
- `template` - Template flag
- `delete_date` - Deletion date (if soft-deleted)
- `deleted_by` - Deleter user ID (if soft-deleted)

**⚠️ Token Warning:** Requesting `permissions` field for all solutions (100+) may exceed token limits due to large permissions objects. Use `list_solutions_by_owner` or request individual solutions instead.

### Notes

- **Cache enabled** by default (4-hour TTL)
- **Client-side filtering** when using `fields` parameter
- **No SmartSuite filter support** - API returns all solutions
- Use `list_solutions_by_owner` for efficient owner filtering

---

## list_solutions_by_owner

List solutions owned by a specific user.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `owner_id` | string | ✅ Yes | User ID of the solution owner |
| `include_activity_data` | boolean | No | Include usage metrics (default: false) |

### Example

```ruby
# List solutions owned by specific user
list_solutions_by_owner('user_abc123')

# With activity data
list_solutions_by_owner('user_abc123', include_activity_data: true)
```

### Response Format

```
=== SOLUTIONS OWNED BY user_abc123 (3 total) ===

--- Solution 1 of 3 ---
id: sol_123abc
name: Sales Pipeline
logo_icon: trending-up
logo_color: green

--- Solution 2 of 3 ---
id: sol_456def
name: Marketing Campaigns
logo_icon: megaphone
logo_color: orange

[... etc]
```

### How It Works

1. Fetches all solutions with permissions data
2. Filters client-side by `owner_id` from `permissions.owners` array
3. Returns only matching solutions with essential fields
4. Much more efficient than requesting permissions for all solutions

### Notes

- **Client-side filtering** after API fetch
- **More efficient** than `list_solutions(fields: ['permissions'])`
- **Cache enabled** (shares cache with `list_solutions`)
- Use `list_members` or `search_member` to find user IDs

---

## analyze_solution_usage

Analyze solution usage to identify inactive or underutilized workspaces.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `days_inactive` | integer | No | Days since last access to consider inactive (default: 90) |
| `min_records` | integer | No | Minimum records to not be empty (default: 10) |

### Example

```ruby
# Default thresholds (90 days, 10 records)
analyze_solution_usage

# Custom thresholds
analyze_solution_usage(days_inactive: 60, min_records: 5)
```

### Response Format

```
=== SOLUTION USAGE ANALYSIS ===

Analysis Date: 2025-01-15T10:30:00Z

Thresholds:
  Days Inactive: 90
  Min Records: 10

Summary:
  Total Solutions: 110
  Inactive: 15 (13.6%)
  Potentially Unused: 8 (7.3%)
  Active: 87 (79.1%)

=== INACTIVE SOLUTIONS (15) ===

--- Solution 1 of 15 ---
id: sol_old123
name: Old Project Tracker
status: active
hidden: false
last_access: 2024-08-15T14:22:00Z (153 days ago)
records_count: 5
members_count: 2
applications_count: 1
automation_count: 0
has_demo_data: false
reason: Never accessed or not accessed in 90+ days with minimal content

[... etc]

=== POTENTIALLY UNUSED SOLUTIONS (8) ===

--- Solution 1 of 8 ---
id: sol_template789
name: Template Workspace
status: active
hidden: false
last_access: null (never accessed)
records_count: 25
members_count: 1
applications_count: 3
automation_count: 2
has_demo_data: true
reason: Never accessed but has significant content

[... etc]
```

### Categorization Logic

**Inactive Solutions:**
- Never accessed OR not accessed in X days (configurable)
- AND minimal records/automations (below thresholds)
- Likely candidates for deletion or archiving

**Potentially Unused Solutions:**
- Never accessed BUT has significant content
- OR not accessed in X days with significant content
- May be templates, API-only solutions, or abandoned projects

**Active Solutions:**
- Accessed within the threshold period
- Regular user activity

### Important Notes

**Primary indicator:** `last_access` timestamp
- Shows when solution was last opened in UI
- Does NOT reflect API-only activity

**Demo data flag:** `has_demo_data` is NOT used for categorization
- Many production solutions contain demo data
- Not a reliable indicator of usage

**"Never accessed" doesn't mean unused:**
- Could be templates
- Could be API-only solutions (data entry via API)
- Could be data repositories (written to but rarely viewed)
- Could be archived/historical data still in use

**High record counts with old last_access:**
- May indicate automated data entry via API
- May indicate data repositories
- Requires manual review to confirm if unused

### Use Cases

**1. Workspace Cleanup:**
```ruby
# Find solutions to archive
analyze_solution_usage(days_inactive: 180)
# Review inactive solutions, confirm with owners, archive
```

**2. License Optimization:**
```ruby
# Find underutilized solutions consuming licenses
analyze_solution_usage(days_inactive: 90, min_records: 10)
# Review potentially unused solutions with members
```

**3. Template Identification:**
```ruby
# Find never-accessed solutions with content
analyze_solution_usage
# Check potentially_unused for templates (has_demo_data: true)
```

### Notes

- **Fetches all solutions** with activity data
- **Client-side analysis** of usage patterns
- **No cache** - always fresh data from API
- **Manual review recommended** before deleting solutions
- **Check with owners** before archiving (use `list_solutions_by_owner`)

---

## get_solution_most_recent_record_update

Get the most recent record update timestamp across all tables in a solution.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `solution_id` | string | ✅ Yes | Solution identifier |

### Example

```ruby
get_solution_most_recent_record_update('sol_123abc456def')
```

### Response Format

```
=== MOST RECENT RECORD UPDATE ===

Solution ID: sol_123abc456def
Last Updated: 2025-01-14T16:45:32Z

This solution has recent data activity.
```

Or if no records:

```
=== MOST RECENT RECORD UPDATE ===

Solution ID: sol_123abc456def
Last Updated: null

No records found in this solution.
```

### How It Works

1. Lists all tables in the solution
2. Queries each table for most recent `last_updated.on` timestamp
3. Returns the maximum timestamp across all tables
4. Returns `null` if no records exist

### Use Cases

**1. Data Activity Check:**
```ruby
# Check if solution has recent data updates
# (even if UI not accessed)
get_solution_most_recent_record_update('sol_123abc')
```

**2. Complement to Usage Analysis:**
```ruby
# Solution shows old last_access but may have API activity
analyze_solution_usage  # Shows old last_access
get_solution_most_recent_record_update('sol_123')  # Shows recent data updates
# Indicates API-only usage
```

**3. Archive Decision Making:**
```ruby
# Before archiving, check for recent data activity
get_solution_most_recent_record_update('sol_old123')
# If null or very old, safe to archive
# If recent, may still be in use via API
```

### Notes

- **Queries all tables** in the solution
- **No cache** - always fresh data
- **Returns null** if no records exist
- **Useful for detecting API-only usage**
- **Complements last_access** from `analyze_solution_usage`

---

## Common Patterns

### Get Solution Details Before Working

```ruby
# 1. List all solutions to find the one you need
list_solutions

# 2. Use the solution_id to filter tables
list_tables(solution_id: 'sol_abc123')

# 3. Work with tables in that solution
list_records('tbl_xyz789', 10, 0, fields: ['status'])
```

### Find Inactive Solutions for Cleanup

```ruby
# 1. Analyze usage
analyze_solution_usage(days_inactive: 90)

# 2. For each inactive solution, check recent data activity
get_solution_most_recent_record_update('sol_old123')

# 3. If no recent activity, check owner
list_solutions_by_owner('user_abc123')

# 4. Confirm with owner before archiving
```

### Find All Solutions Owned by User

```ruby
# 1. Find user ID
search_member('john@example.com')

# 2. List their solutions
list_solutions_by_owner('user_abc123', include_activity_data: true)
```

---

## Best Practices

### 1. Use Minimal Fields

**✅ Good:**
```ruby
# Default essential fields only
list_solutions
```

**❌ Avoid:**
```ruby
# Requesting permissions for all solutions
list_solutions(fields: ['id', 'name', 'permissions'])  // 100+ solutions = token overload
```

### 2. Filter by Owner When Possible

**✅ Good:**
```ruby
# Use dedicated owner filter
list_solutions_by_owner('user_abc123')
```

**❌ Avoid:**
```ruby
# Fetch all + manual filtering
list_solutions(fields: ['permissions'])  // Fetch 100+ solutions with large objects
# Then manually filter in conversation
```

### 3. Use Activity Data Wisely

**✅ Good:**
```ruby
# Only when needed for analysis
analyze_solution_usage  // Automatic activity data
list_solutions_by_owner('user_123', include_activity_data: true)
```

**❌ Avoid:**
```ruby
# Don't fetch activity data unnecessarily
list_solutions(include_activity_data: true)  // Every time
```

### 4. Verify Data Activity Before Archiving

**✅ Good:**
```ruby
# Check both UI and API activity
analyze_solution_usage  // UI activity (last_access)
get_solution_most_recent_record_update('sol_123')  // Data activity
```

**❌ Avoid:**
```ruby
# Only checking UI activity
analyze_solution_usage
# Archive based on last_access alone (may miss API usage)
```

---

## Error Handling

### Solution Not Found

```
Error: Solution not found: sol_xyz123
```

**Solution:** Verify solution ID with `list_solutions`

### Permission Denied

```
Error: 403 Forbidden - Insufficient permissions
```

**Solution:** Check SmartSuite permissions - you may not have access

### User Not Found

```
Error: No solutions found for owner: user_xyz123
```

**Solution:** Verify user ID with `list_members` or `search_member`

---

## Related Documentation

- **[Table Operations](tables.md)** - Work with tables in solutions
- **[Record Operations](records.md)** - Access data in tables
- **[Member Operations](members.md)** - Find user IDs for owner filtering
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior
- **[Usage Analysis Guide](../guides/usage-analysis.md)** - Best practices for solution cleanup

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
