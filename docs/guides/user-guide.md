# User Guide

Complete guide to using SmartSuite MCP Server with Claude.

## Overview

SmartSuite MCP Server enables Claude to interact with your SmartSuite workspace through natural language. Instead of navigating the SmartSuite UI, you can ask Claude to query data, create records, manage tables, and more.

**This guide covers:**
- How to communicate with Claude
- Common workflows and patterns
- Best practices for efficient usage
- Tips for getting better results

---

## Getting Started

### Your First Query

Once installed, simply ask Claude about your SmartSuite data:

```
Show me all my SmartSuite solutions
```

Claude will:
1. Use the `list_solutions` tool
2. Fetch your workspaces
3. Display them in a readable format

### Natural Language Interface

You don't need to know the technical details. Just ask naturally:

**Instead of:**
```
Use list_records with table_id tbl_123, limit 10, fields ['status', 'priority']
```

**Just say:**
```
Show me 10 records from the Tasks table with their status and priority
```

Claude understands context and will:
- Find the right table
- Get the structure
- Query with correct field slugs
- Display results clearly

---

## Common Workflows

### 1. Exploring Your Workspace

**List your solutions:**
```
What SmartSuite solutions do I have access to?
```

**Find tables in a solution:**
```
What tables are in my "Project Management" solution?
```

**Understand table structure:**
```
What fields are in the Tasks table?
```

### 2. Querying Data

**Simple query:**
```
Show me the first 10 tasks
```

**With filtering:**
```
Show me all high-priority tasks that are still active
```

**Specific fields:**
```
List all customers with just their name and email
```

**With pagination:**
```
Show me tasks 11-20
```

### 3. Creating Records

**Basic creation:**
```
Create a new task:
- Title: Review Q4 budget
- Status: Active
- Priority: High
- Assigned to: john@example.com
```

**Batch creation:**
```
Create 3 new tasks for the engineering sprint:
1. Implement user authentication
2. Add password reset flow
3. Write integration tests
```

### 4. Updating Records

**Single update:**
```
Update task "Review Q4 budget" to status "Completed"
```

**Bulk updates:**
```
Mark all tasks assigned to john@example.com as "In Progress"
```

### 5. Data Analysis

**Find patterns:**
```
Which solution has the most records?
```

**Usage analysis:**
```
Show me solutions that haven't been accessed in the last 90 days
```

**Team activity:**
```
What tasks are assigned to the engineering team?
```

### 6. Collaboration

**Add comments:**
```
Add a comment to task "Q4 Planning":
"Updated timeline based on yesterday's meeting"
```

**With assignment:**
```
Add a comment to task "Budget Review" and assign it to sarah@example.com:
"Please review and approve by Friday"
```

**View discussion:**
```
Show me all comments on the "Product Launch" task
```

### 7. Schema Management

**Add fields:**
```
Add a "Department" dropdown field to the Employees table with options:
- Engineering
- Sales
- Marketing
- Support
```

**Update field:**
```
Make the "Priority" field required in the Tasks table
```

---

## How Claude Works With SmartSuite

### Behind the Scenes

When you ask Claude to query data, here's what happens:

1. **Understanding:** Claude parses your request
2. **Planning:** Determines which tools to use
3. **Execution:** Calls SmartSuite MCP Server tools
4. **Caching:** Server checks cache (4-hour TTL)
5. **API Call:** Fetches from SmartSuite if needed
6. **Formatting:** Converts to readable format
7. **Response:** Claude presents results

### Cache-First Strategy

The server aggressively caches data to:
- **Reduce API calls** (stay within rate limits)
- **Speed up responses** (milliseconds vs seconds)
- **Save tokens** (plain text vs JSON)

**Example:**
```
You: Show me 10 tasks
Claude: [Fetches from API, caches, shows results]

You: Now show me tasks 11-20
Claude: [Uses cache, instant response]

You: Show me only high-priority tasks
Claude: [Queries cached data with SQL, instant]
```

### When Cache is Bypassed

Claude will automatically request fresh data when:
- You ask for "latest" or "fresh" data
- Right after creating/updating records
- You explicitly request it

**Example:**
```
Show me the latest tasks (bypass cache)
```

---

## Best Practices

### 1. Be Specific About What You Need

**✅ Good:**
```
Show me the title, status, and priority for active tasks
```

**❌ Less efficient:**
```
Show me all task details
```

**Why:** Requesting only needed fields reduces tokens and improves performance.

### 2. Use Filters to Narrow Results

**✅ Good:**
```
Show me high-priority tasks assigned to engineering team
```

**❌ Less efficient:**
```
Show me all tasks
[Then manually scanning through results]
```

**Why:** Filtering at the database level is much faster than scanning in conversation.

### 3. Start Small, Then Expand

**✅ Good:**
```
Show me 10 tasks first

[Review results]

Show me 50 more if needed
```

**❌ Less efficient:**
```
Show me 1000 tasks
[Claude's context fills up quickly]
```

**Why:** Starting small keeps Claude's context manageable.

### 4. Leverage Existing Views

**✅ Good:**
```
Show me records from my "Sales Pipeline" view
```

**❌ Less efficient:**
```
Show me customers where stage is "Prospect" or "Qualified"
and last_contact is within 30 days and assigned_to is sales team...
```

**Why:** Views have pre-configured filters that you can reuse.

### 5. Ask Claude to Explain

If you're unsure how to phrase something:
```
How do I find all overdue tasks?
```

Claude will explain the approach and execute it.

### 6. Request Fresh Data When Needed

After making changes:
```
I just created a new task. Show me the latest tasks with fresh data.
```

Claude will bypass the cache to show your new record.

---

## Advanced Patterns

### Multi-Step Workflows

Claude can handle complex multi-step operations:

**Example: Create Project with Tasks**
```
Create a new project called "Website Redesign" with these tasks:
1. Design mockups (High priority, assigned to design@example.com)
2. Frontend implementation (Medium priority, assigned to dev@example.com)
3. Content migration (Low priority, assigned to content@example.com)
```

Claude will:
1. Create the project record
2. Create each task
3. Link tasks to project
4. Assign to correct users
5. Confirm completion

### Data Migration

**Example: Copy Records Between Tables**
```
Copy all "Completed" tasks from Q3 Projects table to Archive table
```

Claude will:
1. Query source table
2. Filter completed tasks
3. Create records in destination
4. Handle field mapping
5. Report results

### Reporting and Analysis

**Example: Generate Status Report**
```
Give me a summary of our project status:
- Total projects
- Projects by status
- Overdue projects
- Top assignees by task count
```

Claude will:
1. Query projects table
2. Analyze data
3. Generate formatted report
4. Highlight key insights

### Bulk Operations

**Example: Update Multiple Records**
```
For all tasks assigned to john@example.com where status is "Pending",
change the status to "In Progress" and add a comment "Starting this week"
```

Claude will:
1. Find matching tasks
2. Update each record
3. Add comments
4. Report changes

---

## Tips for Better Results

### 1. Provide Context

**Better:**
```
In the Customer Success solution's "Support Tickets" table,
show me all open tickets from the last week
```

**Good but less precise:**
```
Show me recent open tickets
```

### 2. Specify Exactly What You Want

**Better:**
```
Show me: ticket ID, customer name, priority, and created date
```

**Good but returns more data:**
```
Show me ticket information
```

### 3. Use SmartSuite Terminology

**Terms Claude understands:**
- **Solutions** = Workspaces
- **Applications/Tables** = Tables containing records
- **Fields** = Columns
- **Records** = Rows
- **Views** = Saved filter/sort configurations

### 4. Ask for Explanations

```
Why are my results empty?
```

Claude will check:
- Filter criteria
- Table permissions
- Data existence
- Cache state

### 5. Request Structured Output

```
Create a markdown table of all projects showing name, status, and owner
```

Claude will format results as requested.

---

## Understanding Responses

### Record Listings

```
=== RECORDS (10 of 127 total) ===

--- Record 1 of 10 ---
id: rec_123abc
title: Q4 Planning
status: Active
priority: High
```

**Key information:**
- "10 of 127 total" - 10 shown, 127 exist (helps with pagination)
- Record ID - Unique identifier
- Field values - As requested

### Summary Statistics

When you ask for analysis:
```
Summary:
  Total Projects: 45
  Active: 32 (71%)
  Completed: 10 (22%)
  On Hold: 3 (7%)

Top Assignees:
  1. Sarah Johnson - 15 projects
  2. Mike Chen - 12 projects
  3. Lisa Garcia - 8 projects
```

### Error Messages

If something goes wrong:
```
Error: Table not found: tbl_xyz123
```

Claude will:
- Explain the error
- Suggest solutions
- Try alternative approaches

---

## Common Questions

### Q: How often is data refreshed?

**A:** Cache is refreshed every 4 hours automatically. You can request fresh data anytime by asking for "latest" data.

### Q: Can Claude create tables?

**A:** Yes! Just describe the table structure you want:
```
Create a new "Inventory" table with fields:
- Item Name (text, required)
- Quantity (number)
- Location (single select: Warehouse A, Warehouse B, Warehouse C)
- Last Restocked (date)
```

### Q: How do I filter by date?

**A:** Use natural language:
```
Show me tasks created in the last 7 days
Show me events scheduled for next week
Show me projects with deadline before end of month
```

### Q: Can I export data?

**A:** Claude can format data for export:
```
Export all customers to CSV format
```

### Q: What if I don't know the field names?

**A:** Just ask:
```
What fields are available in the Customers table?
```

### Q: Can Claude help with permissions?

**A:** Yes, for information:
```
Who has access to the "Sales Pipeline" solution?
Which tables am I allowed to edit?
```

But Claude cannot grant or modify permissions.

---

## Troubleshooting

### Results Are Empty

**Check:**
1. Filter criteria too restrictive?
2. Using correct table name?
3. Do records actually exist?

**Try:**
```
Show me ALL records from [table] (no filters)
```

### Can't Find Table

**Solution:**
```
What tables are in my [solution name] solution?
```

Then use the exact table name Claude shows.

### Data Seems Outdated

**Solution:**
```
Show me [data] with fresh data
```

Or:
```
Bypass cache and show me [data]
```

### Too Many Results

**Solution:**
```
Show me just 10 [items] to start
```

Then paginate if needed.

---

## Next Steps

**Learn more:**
- **[Filtering Guide](filtering-guide.md)** - Master advanced filters
- **[Caching Guide](caching-guide.md)** - Understand caching behavior
- **[Performance Guide](performance-guide.md)** - Optimize your queries
- **[API Reference](../api/)** - Complete technical reference

**Try examples:**
- **[Basic Workflow](../examples/basic-workflow.md)** - Step-by-step tutorial
- **[Advanced Filtering](../examples/advanced-filtering.md)** - Complex queries

**Get help:**
- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
