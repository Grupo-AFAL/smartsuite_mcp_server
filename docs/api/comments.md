# Comment Operations

Complete reference for SmartSuite comment operations.

## Overview

Comments provide collaboration features for records. Users can add notes, mention team members, and assign follow-up tasks through the commenting system.

**Key Features:**
- List all comments on a record
- Add new comments with plain text
- Assign comments to users
- Automatic rich text formatting
- Track comment threads and reactions

---

## list_comments

Retrieve all comments for a specific record.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `record_id` | string | ✅ Yes | Record identifier |

### Example

```ruby
list_comments('rec_68e3d5fb98c0282a4f1e2614')
```

### Response Format

```
=== COMMENTS ON RECORD rec_68e3d5fb98c0282a4f1e2614 (5 total) ===

--- Comment 1 of 5 ---
id: comment_123abc
key: 1
created_on: 2025-01-10T14:30:00Z
member: user_abc123 (John Doe)
message: Started working on this task
assigned_to: null
followers: []
reactions: []

--- Comment 2 of 5 ---
id: comment_456def
key: 2
created_on: 2025-01-11T09:15:00Z
member: user_def456 (Jane Smith)
message: Need clarification on requirements
assigned_to: user_abc123
followers: [user_abc123]
reactions: [👍, ❤️]

[... etc]
```

### Comment Information

Each comment includes:
- `id` - Comment unique identifier
- `key` - Comment number on the record (sequential)
- `message` - Comment text (plain text preview)
- `record` - Record ID the comment belongs to
- `application` - Table ID
- `solution` - Solution ID
- `member` - User ID of comment creator
- `created_on` - Creation timestamp
- `assigned_to` - Optional assigned user ID
- `followers` - Array of user IDs following the comment
- `reactions` - Array of emoji reactions

### Use Cases

**1. View Comment Thread:**
```ruby
# Get all comments on a record
list_comments('rec_task123')

# Review conversation
# See who commented and when
```

**2. Find Assigned Comments:**
```ruby
# List comments
list_comments('rec_abc123')

# Look for comments with assigned_to values
# Follow up on assignments
```

**3. Track Engagement:**
```ruby
# List comments
list_comments('rec_project456')

# Check followers and reactions
# See who's engaged with the record
```

### Notes

- **No cache** - always fetches from API
- **Sorted by creation date** (oldest first)
- **Plain text preview** in response (full rich text available in raw data)
- **Use key** for human-readable comment numbering

---

## add_comment

Add a new comment to a record.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `table_id` | string | ✅ Yes | Table identifier |
| `record_id` | string | ✅ Yes | Record identifier |
| `message` | string | ✅ Yes | Comment text (plain text) |
| `assigned_to` | string | No | User ID to assign comment to |

### Basic Example

```ruby
add_comment(
  table_id: 'tbl_6796989a7ee3c6b731717836',
  record_id: 'rec_68e3d5fb98c0282a4f1e2614',
  message: 'Started working on this task. Will update by EOD.'
)
```

### With Assignment

```ruby
add_comment(
  table_id: 'tbl_abc123',
  record_id: 'rec_xyz789',
  message: 'Please review the attached documents.',
  assigned_to: 'user_abc123'
)
```

### Message Format

**Plain text input** (automatic conversion):
```ruby
add_comment(
  table_id: 'tbl_123',
  record_id: 'rec_456',
  message: 'This is a simple comment'
)
```

The server automatically formats plain text to SmartSuite's rich text format:
```
Input: "This is a simple comment"

Formatted to:
{
  "data": {
    "type": "doc",
    "content": [{
      "type": "paragraph",
      "content": [{
        "type": "text",
        "text": "This is a simple comment"
      }]
    }]
  }
}
```

**Multi-line text:**
```ruby
message = <<~TEXT
  This is a multi-line comment.

  It has multiple paragraphs.

  Very useful for detailed notes.
TEXT

add_comment(
  table_id: 'tbl_123',
  record_id: 'rec_456',
  message: message
)
```

### Response Format

Returns the created comment:

```
=== COMMENT ADDED ===

id: comment_new123
key: 6
record: rec_68e3d5fb98c0282a4f1e2614
created_on: 2025-01-15T16:45:00Z
member: user_current (You)
message: Started working on this task. Will update by EOD.
assigned_to: null

Comment successfully added to record.
```

### Assignment

When assigning a comment:
1. User receives notification
2. Comment appears in their assigned list
3. Creates follow-up task
4. User becomes a follower automatically

```ruby
# Assign to user
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_task123',
  message: '@JohnDoe please review and approve',
  assigned_to: 'user_abc123'  # John's user ID
)
```

### Use Cases

**1. Status Updates:**
```ruby
# Add progress update
add_comment(
  table_id: 'tbl_projects',
  record_id: 'rec_proj456',
  message: 'Completed phase 1. Moving to phase 2 tomorrow.'
)
```

**2. Request Review:**
```ruby
# Request review with assignment
add_comment(
  table_id: 'tbl_documents',
  record_id: 'rec_doc789',
  message: 'Please review the attached proposal and provide feedback by Friday.',
  assigned_to: 'user_manager'
)
```

**3. Team Collaboration:**
```ruby
# Add collaborative note
add_comment(
  table_id: 'tbl_ideas',
  record_id: 'rec_idea123',
  message: 'Great idea! I think we should also consider adding mobile support.'
)
```

**4. Issue Tracking:**
```ruby
# Log issue
add_comment(
  table_id: 'tbl_bugs',
  record_id: 'rec_bug456',
  message: 'Reproduced the issue on staging. Root cause is in the auth module.'
)
```

### Notes

- **No cache** - direct API call
- **Plain text input** - automatic formatting
- **Assignment notifications** sent immediately
- **Creator becomes follower** automatically
- **Supports multi-line** text with line breaks

---

## Common Patterns

### Add Status Update

```ruby
# 1. Update record status
update_record('tbl_tasks', 'rec_task123', {
  'status' => 'In Progress'
})

# 2. Add comment explaining change
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_task123',
  message: 'Moving to In Progress. Started implementation today.'
)
```

### Request Action with Assignment

```ruby
# 1. Find user to assign
search_member('john.doe@example.com')
# Returns: user_abc123

# 2. Add comment with assignment
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_task456',
  message: 'Please complete code review by EOD Wednesday.',
  assigned_to: 'user_abc123'
)
```

### Track Discussion Thread

```ruby
# 1. View existing comments
list_comments('rec_discussion789')

# 2. Add reply to discussion
add_comment(
  table_id: 'tbl_discussions',
  record_id: 'rec_discussion789',
  message: 'I agree with the approach suggested in comment #3.'
)
```

### Document Decision

```ruby
# 1. Add decision comment
add_comment(
  table_id: 'tbl_projects',
  record_id: 'rec_proj123',
  message: <<~DECISION
    Decision: We will proceed with Option B.

    Reasoning:
    - Better long-term scalability
    - Lower implementation cost
    - Team has relevant experience

    Next steps:
    - Create implementation plan
    - Schedule kickoff meeting
  DECISION
)

# 2. Update record to reflect decision
update_record('tbl_projects', 'rec_proj123', {
  'status' => 'Approved',
  'selected_option' => 'Option B'
})
```

---

## Best Practices

### 1. Use Clear, Actionable Messages

**✅ Good:**
```ruby
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_123',
  message: 'Blocked on API access. Need credentials from IT by Thursday.'
)
```

**❌ Avoid:**
```ruby
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_123',
  message: 'stuck'  # Too vague
)
```

### 2. Assign When Action Required

**✅ Good:**
```ruby
# Assign when specific person needs to act
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_123',
  message: 'Please approve budget before EOD.',
  assigned_to: 'user_manager'  # Specific action for specific person
)
```

**❌ Avoid:**
```ruby
# Don't assign for general updates
add_comment(
  table_id: 'tbl_tasks',
  record_id: 'rec_123',
  message: 'Task completed.',
  assigned_to: 'user_someone'  # No action needed
)
```

### 3. Include Context in Comments

**✅ Good:**
```ruby
add_comment(
  table_id: 'tbl_bugs',
  record_id: 'rec_bug456',
  message: <<~COMMENT
    Bug reproduced on staging (v2.1.3).

    Steps:
    1. Login as admin
    2. Navigate to reports
    3. Click export button

    Error: "Export failed - permission denied"

    Assigned to Sarah for investigation.
  COMMENT,
  assigned_to: 'user_sarah'
)
```

**❌ Avoid:**
```ruby
add_comment(
  table_id: 'tbl_bugs',
  record_id: 'rec_bug456',
  message: 'Bug found',  # No context
  assigned_to: 'user_sarah'
)
```

### 4. Review Comments Before Major Actions

**✅ Good:**
```ruby
# Check for blocking comments before closing
list_comments('rec_task123')
# Review for unresolved issues

# If clear, update status
update_record('tbl_tasks', 'rec_task123', {
  'status' => 'Completed'
})
```

**❌ Avoid:**
```ruby
# Close without checking comments
update_record('tbl_tasks', 'rec_task123', {
  'status' => 'Completed'
})
# May miss important discussion
```

---

## Error Handling

### Record Not Found

```
Error: Record not found: rec_xyz123
```

**Solution:** Verify record ID with `list_records`

### Table Not Found

```
Error: Table not found: tbl_xyz123
```

**Solution:** Verify table ID with `list_tables`

### User Not Found (for assignment)

```
Error: User not found: user_xyz123
```

**Solution:**
- Verify user ID with `search_member` or `list_members`
- User may not have access to the solution

### Permission Denied

```
Error: 403 Forbidden - Insufficient permissions
```

**Solution:**
- Check you have comment permissions on the record
- Verify solution access

---

## Related Documentation

- **[Record Operations](records.md)** - Work with records
- **[Member Operations](members.md)** - Find user IDs for assignments
- **[User Guide](../guides/user-guide.md)** - Collaboration workflows
- **[Caching Guide](../guides/caching-guide.md)** - Understanding cache behavior

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
