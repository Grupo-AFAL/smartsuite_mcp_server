# Basic Workflow Tutorial

Step-by-step tutorial covering fundamental SmartSuite MCP Server operations.

## Objective

By the end of this tutorial, you'll be able to:
- Explore your SmartSuite workspace
- Query data with basic filters
- Create and update records
- Understand how caching works
- Optimize for performance and token usage

**Time:** 15-20 minutes
**Level:** Beginner
**Prerequisites:** SmartSuite MCP Server installed and configured

---

## Part 1: Exploring Your Workspace

### Step 1: List Your Solutions

**What you'll do:** Discover what solutions (workspaces) you have access to.

**Say to Claude:**
```
Show me all my SmartSuite solutions
```

**Expected response:**
```
=== SOLUTIONS (5 total) ===

--- Solution 1 of 5 ---
id: sol_abc123
name: Project Management
logo_icon: tasks
logo_color: blue

--- Solution 2 of 5 ---
id: sol_def456
name: Customer Success
logo_icon: users
logo_color: green

... (3 more solutions)
```

**What happened:**
- Claude used the `list_solutions` tool
- Retrieved all solutions from SmartSuite API
- Formatted results as plain text
- **First query:** Took ~500ms (API call)
- **Cache:** Solutions cached for 4 hours

---

### Step 2: Find Tables in a Solution

**What you'll do:** See what tables exist in the "Project Management" solution.

**Say to Claude:**
```
What tables are in my Project Management solution?
```

**Expected response:**
```
=== TABLES (3 total) ===

--- Table 1 of 3 ---
id: tbl_proj_123
name: Projects
solution_id: sol_abc123

--- Table 2 of 3 ---
id: tbl_task_456
name: Tasks
solution_id: sol_abc123

--- Table 3 of 3 ---
id: tbl_team_789
name: Team Members
solution_id: sol_abc123
```

**What happened:**
- Claude used `list_tables` tool with solution filter
- **Performance:** ~300ms (API call, now cached)

---

### Step 3: Understand Table Structure

**What you'll do:** See what fields are available in the Tasks table.

**Say to Claude:**
```
What fields are in the Tasks table?
```

**Expected response:**
```
=== TABLE STRUCTURE: Tasks ===

Field 1: title
  Type: textfield
  Required: true

Field 2: status
  Type: singleselectfield
  Choices: To Do, In Progress, Completed, Blocked

Field 3: priority
  Type: singleselectfield
  Choices: Low, Medium, High, Critical

Field 4: assigned_to
  Type: assignedtofield

Field 5: due_date
  Type: duedatefield

Field 6: description
  Type: richtextareafield

... (additional fields)
```

**What happened:**
- Claude used `get_table` tool
- Retrieved filtered structure (83.8% smaller than full API response)
- Shows essential information: slug, type, choices
- **Token savings:** ~900 tokens vs full structure

**💡 Tip:** Note the field slugs (`title`, `status`, etc.) - you'll use these to query data.

---

## Part 2: Querying Data

### Step 4: Simple Query

**What you'll do:** Get first 10 tasks.

**Say to Claude:**
```
Show me 10 tasks with their title, status, and priority
```

**Expected response:**
```
=== RECORDS (10 of 127 total) ===

--- Record 1 of 10 ---
id: rec_001
title: Q4 Planning
status: In Progress
priority: High

--- Record 2 of 10 ---
id: rec_002
title: Budget Review
status: To Do
priority: Critical

... (8 more records)
```

**What happened:**
- Claude used `list_records` tool
- **Fields parameter:** `['title', 'status', 'priority']` (you specified)
- **Cache miss:** First query took ~1.2 seconds
  - Fetched ALL 127 tasks from API (pagination)
  - Stored in SQLite cache
  - Returned first 10
- **Important:** Cache now contains ALL 127 tasks

**💡 Key insight:** "10 of 127 total" helps Claude know there are more records to fetch if needed.

---

### Step 5: Query with Filtering

**What you'll do:** Find only high-priority tasks.

**Say to Claude:**
```
Show me high-priority tasks
```

**Expected response:**
```
=== RECORDS (23 of 127 total) ===

--- Record 1 of 23 ---
id: rec_002
title: Budget Review
status: To Do
priority: High

--- Record 2 of 23 ---
id: rec_001
title: Q4 Planning
status: In Progress
priority: High

... (21 more records)
```

**What happened:**
- Claude used `list_records` with filter
- **Filter:** `{operator: 'and', fields: [{field: 'priority', comparison: 'is', value: 'High'}]}`
- **Cache hit!** Query took ~10ms (instant)
- **No API call** - filtered cached data with SQL
- **Performance:** 99% faster than API call

**💡 Tip:** Subsequent queries on same table are instant because all records are cached.

---

### Step 6: Pagination

**What you'll do:** Get next 10 high-priority tasks.

**Say to Claude:**
```
Show me the next 10 high-priority tasks
```

**Expected response:**
```
=== RECORDS (10 of 23 total, offset: 10) ===

--- Record 11 of 23 ---
id: rec_045
title: Security Audit
status: Blocked
priority: High

... (9 more records)
```

**What happened:**
- Claude used `offset: 10` parameter
- **Cache hit** - still instant (~10ms)
- **No API call**

---

## Part 3: Creating and Updating Data

### Step 7: Create a Record

**What you'll do:** Add a new task.

**Say to Claude:**
```
Create a new task:
- Title: "Review documentation"
- Status: "To Do"
- Priority: "Medium"
- Due date: "2025-01-20"
```

**Expected response:**
```
=== CREATED RECORD ===

id: rec_new_128
title: Review documentation
status: To Do
priority: Medium
due_date: 2025-01-20
created_on: 2025-01-15T10:30:00Z
```

**What happened:**
- Claude used `create_record` tool
- **API call:** ~400ms
- **Cache NOT updated** (by design)
- **Important:** Cache still shows 127 records (old count)

---

### Step 8: Query Fresh Data After Mutation

**What you'll do:** See the newly created record.

**Say to Claude:**
```
Show me the latest tasks with fresh data
```

**Expected response:**
```
=== RECORDS (10 of 128 total) ===

--- Record 1 of 10 ---
id: rec_new_128
title: Review documentation
status: To Do
priority: Medium
due_date: 2025-01-20

... (9 more recent records)
```

**What happened:**
- Claude used `bypass_cache: true` parameter
- **Cache refreshed:** Fetched all 128 tasks from API (~1.5 seconds)
- **Cache updated:** Now shows correct count
- **Next queries:** Will use new cache (instant)

**💡 Key learning:** After creating/updating records, request "fresh data" or "latest" to bypass cache.

---

### Step 9: Update a Record

**What you'll do:** Change task status.

**Say to Claude:**
```
Update task "Review documentation" to status "In Progress"
```

**Expected response:**
```
=== UPDATED RECORD ===

id: rec_new_128
title: Review documentation
status: In Progress
priority: Medium
due_date: 2025-01-20
updated_on: 2025-01-15T10:35:00Z
```

**What happened:**
- Claude used `update_record` tool
- **API call:** ~300ms
- **Cache:** Still shows old status (not invalidated)

---

### Step 10: Verify Update

**Say to Claude:**
```
Show me the "Review documentation" task with fresh data
```

**Expected response:**
```
--- Record ---
id: rec_new_128
title: Review documentation
status: In Progress  ← Updated!
priority: Medium
due_date: 2025-01-20
```

**What happened:**
- `bypass_cache: true` fetched fresh data
- Cache refreshed with updated status

---

## Part 4: Understanding Cache Behavior

### Cache Hit vs Cache Miss

**Scenario 1: Cache Hit (Fast)**
```
You: Show me 10 tasks
Claude: [Instant response - 10ms]
```
- Cache valid (< 4 hours old)
- Query SQLite locally
- **Performance:** 5-20ms
- **API calls:** 0

**Scenario 2: Cache Miss (Slower First Time)**
```
You: Show me 10 tasks
Claude: [First time - 1200ms]
```
- Cache invalid/expired
- Fetch ALL tasks from API
- Store in SQLite
- Then query
- **Performance:** 500-2000ms (one-time cost)
- **API calls:** 2-5 (pagination)

**Scenario 3: After Cache Miss**
```
You: Show me next 10 tasks
Claude: [Instant response - 10ms]
```
- Cache now valid
- Back to fast queries
- **Performance:** 5-20ms
- **API calls:** 0

---

### Cache TTL (Time To Live)

**Default:** 4 hours

**What it means:**
- Cache valid for 4 hours after last refresh
- After 4 hours, cache expires
- Next query automatically refreshes cache

**Example timeline:**
```
10:00 AM - First query → Cache refreshed
10:01 AM - Query → Cache hit (instant)
11:00 AM - Query → Cache hit (instant)
2:00 PM  - Query → Cache hit (instant)
2:01 PM  - Cache expires
2:05 PM  - Query → Cache miss → Refresh → Cache hit again
```

---

## Part 5: Performance Optimization

### Best Practice 1: Request Only Needed Fields

**❌ Wasteful:**
```
Show me all task fields
```
Returns 15 fields × 10 records = ~1500 tokens

**✅ Efficient:**
```
Show me task title and status
```
Returns 2 fields × 10 records = ~200 tokens

**Savings:** 87% fewer tokens

---

### Best Practice 2: Use Small Limits Initially

**❌ Wasteful:**
```
Show me 1000 tasks
```
- Fills Claude's context quickly
- Hard to review
- Most records unused

**✅ Efficient:**
```
Show me 10 tasks first
[Review]
Show me 50 more if needed
```
- Start small
- Expand as needed
- Keeps context manageable

---

### Best Practice 3: Filter Early

**❌ Inefficient:**
```
Show me all 1000 tasks
[Manually scan for high-priority ones]
```

**✅ Efficient:**
```
Show me high-priority tasks
```
- Filters at database level
- Returns only relevant records
- Faster, fewer tokens

---

### Best Practice 4: Leverage Cache

**❌ Bypassing unnecessarily:**
```
Show me latest tasks (bypass cache)
Show me latest tasks (bypass cache)
Show me latest tasks (bypass cache)
```
Every query hits API unnecessarily.

**✅ Smart caching:**
```
Show me tasks
Show me high-priority tasks
Show me tasks by assignee
```
All use same cache (instant).

Only bypass when needed:
```
[After creating records]
Show me latest tasks with fresh data
```

---

## Part 6: Common Patterns

### Pattern 1: Explore → Query → Analyze

```
1. What solutions do I have?
   → See workspace structure

2. What tables are in "CRM" solution?
   → Find relevant tables

3. What fields are in "Customers" table?
   → Understand schema

4. Show me 10 customers with name and email
   → Query specific data

5. Show me customers where status is "Active"
   → Filter and analyze
```

**API calls:** 5 (first time), then 0 (all cached)

---

### Pattern 2: Create → Verify → Update

```
1. Create a new project:
   - Name: "Website Redesign"
   - Status: "Planning"
   - Budget: 50000

2. Show me the latest projects with fresh data
   → Verify creation

3. Update "Website Redesign" status to "In Progress"

4. Show me the project with fresh data
   → Verify update
```

**API calls:** 5 total (create + refresh + update + refresh)

---

### Pattern 3: Bulk Analysis

```
1. Show me 100 tasks
   → Cache all tasks (one-time cost)

2. How many are high priority?
   → Query cache (instant)

3. How many are overdue?
   → Query cache (instant)

4. Group by assignee
   → Query cache (instant)

5. Show me tasks created this week
   → Query cache (instant)
```

**API calls:** 1 (initial fetch), then 0 for all analysis

---

## Summary

### What You Learned

✅ **Exploring:**
- List solutions and tables
- Get table structures
- Understand field types

✅ **Querying:**
- Simple queries with field selection
- Filtering by criteria
- Pagination through results

✅ **Mutating:**
- Create new records
- Update existing records
- Bypass cache for fresh data

✅ **Caching:**
- Cache hit vs cache miss
- TTL (4 hours)
- When to bypass cache

✅ **Optimizing:**
- Request minimal fields
- Use small limits
- Filter early
- Leverage cache

---

### Key Takeaways

1. **First query is slow, rest are instant** - Cache-first strategy
2. **Bypass cache after mutations** - Get fresh data when needed
3. **Request only needed fields** - Save tokens
4. **Filter at database level** - Faster and more efficient
5. **Cache expires after 4 hours** - Automatic refresh

---

### Performance Comparison

**Before optimization (no caching):**
```
Query 1: 1000ms
Query 2: 1000ms
Query 3: 1000ms
Total: 3 seconds, 6 API calls
```

**After optimization (with caching):**
```
Query 1: 1000ms (cache miss)
Query 2: 10ms (cache hit)
Query 3: 10ms (cache hit)
Total: 1.02 seconds, 2 API calls

Improvement: 66% faster, 66% fewer API calls
```

---

## Next Steps

**Ready for more?**
- **[Advanced Filtering](advanced-filtering.md)** - Complex query patterns
- **[Filtering Guide](../guides/filtering-guide.md)** - Complete filter reference
- **[Performance Guide](../guides/performance-guide.md)** - Detailed optimization
- **[Caching Guide](../guides/caching-guide.md)** - Deep dive into caching

**Need help?**
- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [User Guide](../guides/user-guide.md)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)

---

## Practice Exercises

**Try these on your own:**

1. **Exercise 1:** Find all completed tasks from last week
2. **Exercise 2:** Create 3 new tasks with different priorities
3. **Exercise 3:** Query tasks, then query filtered subset without hitting API
4. **Exercise 4:** Update a task and verify the change with fresh data
5. **Exercise 5:** Analyze task distribution by status using cache

**Check your understanding:**
- Can you explain when cache is refreshed?
- Do you know which queries hit the API vs cache?
- Can you optimize a query to use fewer tokens?

---

Congratulations! You've completed the basic workflow tutorial. You now understand the fundamentals of SmartSuite MCP Server and are ready for more advanced patterns.
