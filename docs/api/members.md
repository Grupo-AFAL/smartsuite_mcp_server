# Member Operations

Complete reference for SmartSuite member (user and team) operations.

## Overview

Members are users in your SmartSuite workspace. Teams are groups of users that can be assigned permissions. The server provides tools to list members, search for users, and manage teams.

**Key Features:**
- List all workspace members
- Search members by name or email
- Filter members by solution access
- List and get team information
- Cache-first strategy (4-hour TTL)

---

## list_members

List all members (users) in your SmartSuite workspace.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | No | Max members to return (default: 100) |
| `offset` | integer | No | Pagination offset (default: 0) |
| `solution_id` | string | No | Filter by solution access |

### Basic Example

```ruby
# List all members
list_members
```

### Response Format

```
=== MEMBERS (45 total) ===

--- Member 1 of 45 ---
id: user_abc123def456
email: john.doe@example.com
first_name: John
last_name: Doe
role: Member
status: active

--- Member 2 of 45 ---
id: user_789ghi012jkl
email: jane.smith@example.com
first_name: Jane
last_name: Smith
role: Admin
status: active

[... etc]
```

### With Pagination

```ruby
# First page (100 members)
list_members(limit: 100, offset: 0)

# Second page
list_members(limit: 100, offset: 100)

# Third page
list_members(limit: 100, offset: 200)
```

### Filter by Solution

```ruby
# List only members with access to specific solution
list_members(solution_id: 'sol_abc123')
```

Returns only members who have permissions in that solution. This is more efficient than fetching all members when you only need solution-specific users.

### Member Information

Each member includes:
- `id` - User identifier (use for filtering, assignments)
- `email` - Email address
- `first_name` - First name
- `last_name` - Last name
- `role` - Workspace role (Admin, Member, etc.)
- `status` - Account status (active, inactive)
- `avatar` - Avatar URL (if set)
- `created` - Account creation date
- `last_login` - Last login timestamp

### Use Cases

**1. Find User ID for Filtering:**
```ruby
# List all members
list_members

# Find user by email
# Look for: jane.smith@example.com
# Get: user_abc123

# Use ID in filters
list_records('tbl_tasks', 10, 0,
  fields: ['title', 'assigned_to'],
  filter: {
    operator: 'and',
    fields: [{
      field: 'assigned_to',
      comparison: 'has_any_of',
      value: ['user_abc123']
    }]
  }
)
```

**2. Get Solution Members:**
```ruby
# Find members with access to solution
list_members(solution_id: 'sol_abc123')

# Use for solution-specific operations
list_solutions_by_owner('user_abc123')
```

**3. Bulk User Lookup:**
```ruby
# Get all members for reference
list_members(limit: 1000)

# Use to map user IDs to names in UI
```

### Notes

- **Cache enabled** (4-hour TTL)
- **Workspace-level** listing (not per-solution unless filtered)
- **Use search_member** for quick lookups by name/email
- **Endpoint:** `/api/v1/members/list/` (not `/applications/members/`)

---

## search_member

Search for members by name or email.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | ✅ Yes | Search query (name or email) |

### Example

```ruby
# Search by email
search_member('john@example.com')

# Search by name
search_member('John Doe')

# Search by partial match
search_member('smith')
```

### Response Format

```
=== MEMBER SEARCH RESULTS (3 matching "smith") ===

--- Member 1 of 3 ---
id: user_abc123
email: john.smith@example.com
first_name: John
last_name: Smith
role: Member
status: active

--- Member 2 of 3 ---
id: user_def456
email: jane.smithson@example.com
first_name: Jane
last_name: Smithson
role: Admin
status: active

--- Member 3 of 3 ---
id: user_ghi789
email: bob.jones@smith.com
first_name: Bob
last_name: Jones
role: Member
status: active
```

### Search Behavior

**Case-insensitive** search across:
- Email address
- First name
- Last name
- Full name (first + last)

**Returns:** Only matching members (filtered server-side for efficiency)

### Use Cases

**1. Quick User Lookup:**
```ruby
# Find specific user
search_member('john.doe@example.com')
# Get their user ID

# Use in operations
list_solutions_by_owner('user_abc123')
```

**2. Find User for Assignment:**
```ruby
# Search for user
search_member('Jane Smith')
# Get: user_xyz789

# Assign record to user
update_record('tbl_tasks', 'rec_123', {
  'assigned_to' => ['user_xyz789']
})
```

**3. Verify User Exists:**
```ruby
# Check if email exists in workspace
search_member('newuser@example.com')
# Returns empty if not found
```

### Notes

- **More efficient** than `list_members` for specific lookups
- **Server-side filtering** - only matching members returned
- **Case-insensitive** matching
- **Partial matches** supported (e.g., "smith" matches "Smith", "Smithson", etc.)

---

## list_teams

List all teams in your SmartSuite workspace.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | No | Max teams to return (default: 1000) |
| `offset` | integer | No | Pagination offset (default: 0) |

### Example

```ruby
# List all teams
list_teams
```

### Response Format

```
=== TEAMS (8 total) ===

--- Team 1 of 8 ---
id: team_abc123
name: Engineering
description: Engineering team members
member_count: 12
created: 2024-01-15T10:30:00Z

--- Team 2 of 8 ---
id: team_def456
name: Sales
description: Sales team members
member_count: 8
created: 2024-02-01T14:22:00Z

[... etc]
```

### Team Information

Each team includes:
- `id` - Team identifier
- `name` - Team name
- `description` - Team description
- `member_count` - Number of members
- `created` - Creation timestamp
- `updated` - Last update timestamp
- `permissions` - Team permissions object

### Use Cases

**1. List Available Teams:**
```ruby
# See all teams for reference
list_teams

# Use team IDs for permissions
```

**2. Get Team Details:**
```ruby
# List teams
list_teams
# Find team of interest

# Get detailed team info
get_team('team_abc123')
```

### Notes

- **Cache enabled** (4-hour TTL)
- **Workspace-level** listing
- **Endpoint:** `/api/v1/teams/list/` (not `/applications/teams/`)
- **Use get_team** for member details

---

## get_team

Get detailed information about a specific team, including members.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `team_id` | string | ✅ Yes | Team identifier |

### Example

```ruby
get_team('team_abc123def456')
```

### Response Format

```
=== TEAM DETAILS ===

id: team_abc123def456
name: Engineering Team
description: All engineering department members

Members (12):

--- Member 1 ---
id: user_123abc
email: john.doe@example.com
first_name: John
last_name: Doe
role: Member

--- Member 2 ---
id: user_456def
email: jane.smith@example.com
first_name: Jane
last_name: Smith
role: Admin

[... etc]

Permissions:
  Solutions: 5
  Tables: 15
```

### Team Information

Includes:
- Basic team info (id, name, description)
- Complete member list with user details
- Permissions summary
- Creation/update timestamps

### Use Cases

**1. Audit Team Membership:**
```ruby
# Get team details
get_team('team_engineering')

# Review members
# Check permissions
```

**2. Find Team Members:**
```ruby
# Get team
get_team('team_sales')

# Extract member IDs
# Use for filtering or assignments
```

**3. Verify Team Access:**
```ruby
# Check if user is in team
get_team('team_abc123')
# Look for user_xyz789 in members list
```

### Notes

- **Cache enabled** (4-hour TTL)
- **Includes full member details** (not just IDs)
- **Shows permissions** across solutions/tables
- **Use list_teams first** to find team IDs

---

## Common Patterns

### Find User ID by Email

```ruby
# Method 1: Search (fastest for single user)
search_member('john.doe@example.com')
# Returns: user_abc123

# Method 2: List all and filter
list_members
# Manually find john.doe@example.com
# Get: user_abc123
```

### Get Solution Members

```ruby
# 1. List members with access to solution
list_members(solution_id: 'sol_abc123')

# 2. Use member IDs for operations
# - Filter records by assigned user
# - Check solution ownership
# - Audit access
```

### Find Team Members for Assignment

```ruby
# 1. List teams
list_teams

# 2. Get specific team
get_team('team_engineering')

# 3. Extract member IDs
# user_123, user_456, user_789

# 4. Use in record operations
create_record('tbl_tasks', {
  'title' => 'Team Task',
  'assigned_to' => ['user_123', 'user_456', 'user_789']
})
```

### Verify User Exists Before Assignment

```ruby
# 1. Search for user
search_member('newuser@example.com')

# 2. If found, use their ID
# If not found, handle error or invite user

# 3. Assign to record
update_record('tbl_tasks', 'rec_123', {
  'assigned_to' => ['user_found_id']
})
```

---

## Best Practices

### 1. Use search_member for Quick Lookups

**✅ Good:**
```ruby
# Search for specific user
search_member('john@example.com')
# Returns only matching users
```

**❌ Avoid:**
```ruby
# List all members then filter manually
list_members(limit: 1000)
# Then search through conversation for john@example.com
```

### 2. Filter Members by Solution When Possible

**✅ Good:**
```ruby
# Get only solution members
list_members(solution_id: 'sol_abc123')
```

**❌ Avoid:**
```ruby
# Get all workspace members
list_members  # 1000+ members
# Then filter manually
```

### 3. Use get_team for Member Lists

**✅ Good:**
```ruby
# Get team with members
get_team('team_abc123')
# All members included
```

**❌ Avoid:**
```ruby
# List all teams (no member details)
list_teams
# Then list all members separately
# Then manually match
```

### 4. Cache User Lookups

**✅ Good:**
```ruby
# Search once
search_member('john@example.com')
# Use user_abc123 throughout session

# Multiple operations with same user_id
```

**❌ Avoid:**
```ruby
# Repeated searches
search_member('john@example.com')  # Get ID
# ... later ...
search_member('john@example.com')  # Search again
```

---

## Error Handling

### User Not Found

```
=== MEMBER SEARCH RESULTS (0 matching "unknown@example.com") ===

No members found matching query.
```

**Solution:**
- Verify email spelling
- Check if user has access to workspace
- User may need to be invited

### Team Not Found

```
Error: Team not found: team_xyz123
```

**Solution:** Verify team ID with `list_teams`

### Solution Not Found (when filtering)

```
Error: Solution not found: sol_xyz123
```

**Solution:** Verify solution ID with `list_solutions`

---

## Related Documentation

- **[Workspace Operations](workspace.md)** - Filter solutions by owner
- **[Record Operations](records.md)** - Filter records by assigned user
- **[Filtering Guide](../guides/filtering-guide.md)** - User field filtering
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
