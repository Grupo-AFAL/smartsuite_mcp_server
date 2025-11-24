# Performance Guide

Optimize your SmartSuite queries for speed, efficiency, and token usage.

## Overview

SmartSuite MCP Server is designed for performance, but understanding how to use it effectively will give you the best experience. This guide covers optimization strategies, rate limit management, and troubleshooting slow queries.

**What you'll learn:**
- Cache optimization
- Token usage reduction
- Rate limit management
- Query optimization
- Performance monitoring

---

## Performance Fundamentals

### The Performance Triangle

Three factors affect performance:

1. **API Calls** - Stay within rate limits (5 req/sec)
2. **Token Usage** - Keep Claude's context manageable
3. **Response Time** - Get results quickly

**Optimize all three** for best experience.

### Cache-First Strategy

The server uses aggressive caching (4-hour TTL) to optimize all three:

**First query:**
```
You: Show me 100 tasks
Server: Cache MISS → API call → Cache → Response
Time: 1-2 seconds
```

**Subsequent queries:**
```
You: Show me tasks 101-200
Server: Cache HIT → Query SQLite → Response
Time: 5-20 milliseconds (99% faster!)
```

**Result:**
- ✅ 1 API call instead of 2 (50% reduction)
- ✅ Instant responses
- ✅ Minimal tokens (TOON format)

---

## Cache Optimization

### 1. Let Cache Work

**✅ Good:**
```
Show me 10 tasks

[Review results]

Show me 10 more tasks
```

Server uses cache for second query (0 API calls).

**❌ Avoid:**
```
Show me the latest 10 tasks (bypass cache)
Show me 10 more latest tasks (bypass cache)
```

Every query hits the API unnecessarily.

### 2. Query Same Table Multiple Times

**✅ Good:**
```
Show me active tasks
Show me completed tasks
Show me tasks by priority
```

All use the same cache (1 initial API call, then 0).

**❌ Avoid:**
```
Show me latest active tasks (bypass cache)
Show me latest completed tasks (bypass cache)
```

Multiple unnecessary API calls.

### 3. Request Fresh Data Only When Needed

**When to bypass cache:**
- Right after creating/updating records
- When you need guaranteed current data
- Debugging cache issues

**When NOT to bypass:**
- General queries
- Repeated queries on same data
- Pagination through results

### 4. Understand Cache TTL

Cache expires after 4 hours. After expiration:
- Next query refreshes cache automatically
- Subsequent queries use fresh cache
- No manual intervention needed

**Strategy:**
```
[10 AM] First query → Cache refreshed
[10 AM - 2 PM] All queries use cache (fast)
[2:01 PM] Cache expires
[2:05 PM] Next query → Cache refreshed
[2:05 PM - 6 PM] All queries use cache again
```

---

## Token Usage Optimization

### 1. Request Minimal Fields

**Impact:** Reducing fields can save 60-80% tokens.

**✅ Good (minimal):**
```
Show me task ID, status, and priority
```

Response (TOON format):
```
3 of 100 filtered (100 total)
records[3]{id|status|priority}:
rec_123|Active|High
rec_456|Pending|Medium
rec_789|Done|Low
```

**❌ Avoid (all fields):**
```
Show me all task details
```

Response includes: id, title, description, notes, attachments, comments, created_by, created_on, updated_by, updated_on, etc. (10x more tokens)

### 2. Start with Small Limits

**✅ Good:**
```
Show me 10 tasks first

[Review]

Show me 50 more if needed
```

**❌ Avoid:**
```
Show me 1000 tasks
```

1000 records can fill Claude's context quickly.

### 3. TOON Format Responses

The server automatically returns TOON format instead of JSON (50-60% token savings):

**TOON format (what you get):**
```
3 of 3 filtered (3 total)
records[3]{id|status|priority}:
rec_123|Active|High
rec_456|Pending|Medium
rec_789|Done|Low
```

~30-40 tokens

**JSON (what you'd get without optimization):**
```json
{
  "records": [
    {
      "id": "rec_123",
      "status": "Active",
      "priority": "High"
    }
  ]
}
```

~80 tokens (60% more)

### 4. Leverage Table Structure Filtering

`get_table` returns filtered structures (83.8% less data):

**What you get (essential):**
```
slug: status
label: Status
field_type: singleselectfield
choices: [Active, Pending, Completed]
```

**What's removed (UI metadata):**
- Colors, icons, display formats
- Column widths, visibility settings
- Help text, validation rules
- And much more...

---

## Rate Limit Management

### Understanding SmartSuite Limits

**Standard tier:**
- 5 requests/second
- ~300 requests/minute
- ~18,000 requests/hour

**When exceeded:**
- Throttled to 2 requests/second
- 429 errors returned
- Hard limit at 125% of monthly quota

### Stay Within Limits

**1. Use Caching (Default)**

**Without cache:**
```
Query table A → API call
Query table A again → API call
Query table A again → API call
Total: 3 API calls
```

**With cache:**
```
Query table A → API call (cache miss)
Query table A again → Cache hit (0 API calls)
Query table A again → Cache hit (0 API calls)
Total: 1 API call (66% reduction)
```

**2. Batch Operations**

**❌ Avoid sequential:**
```
Create task 1
Create task 2
Create task 3
Total: 3 API calls
```

**✅ Better with Claude:**
```
Create these 3 tasks: [list]
```

Claude can optimize batching when possible.

**3. Monitor Usage**

Check your API usage:
```
Show me API statistics
```

Response shows:
```
Total Calls: 127
By Endpoint:
  /records/list/: 45 calls
  /solutions/: 12 calls
  ...

Top Tables:
  tbl_123: 28 calls
  ...
```

**Action:** If one table has high calls, ensure caching is working.

### Calculate Request Rate

**Per query:**
```
Before: Reset API stats
[Run queries]
After: Check API stats

Result: X calls in Y seconds = X/Y req/sec
```

**Target:** < 5 req/sec average

**If exceeded:**
- Increase cache usage
- Use `refresh_cache` tool sparingly (only when needed)
- Space out bulk operations

---

## Query Optimization

### 1. Filter Early

**✅ Good:**
```
Show me high-priority active tasks
```

Filters at database level (fast).

**❌ Avoid:**
```
Show me all 10,000 tasks

[Then manually review for high-priority active ones]
```

Fetches all records, wastes tokens.

### 2. Use Pagination

**✅ Good:**
```
Show me 50 tasks

[Review]

Show me next 50
```

**❌ Avoid:**
```
Show me all 5,000 tasks at once
```

### 3. Leverage Views

**✅ Good:**
```
Show me records from "Sales Pipeline" view
```

View has pre-configured filters (efficient).

**❌ Avoid:**
```
Show me all customers where status is "Prospect" and last_contact within 30 days and assigned_to sales team and industry is "Technology" and deal_size > 10000...
```

Complex filter every time (inefficient).

### 4. Request Only What You Need

**✅ Good:**
```
Show me customer names and emails
```

**❌ Avoid:**
```
Show me all customer information
```

Then only using name and email.

---

## Performance Patterns

### Pattern 1: Explore Then Query

**Fast approach:**
```
1. What tables are in my solution? [Cache hit after first time]
2. What fields are in Customers table? [Cache hit]
3. Show me 10 customers [Cache hit after first time]
4. Show me customers where... [Cache hit, SQL filter]
```

Total API calls: 3 (first time), then 0

### Pattern 2: Bulk Analysis

**Efficient:**
```
1. Show me 100 tasks [1 API call, cached]
2. How many are high priority? [0 API calls, query cache]
3. How many are overdue? [0 API calls, query cache]
4. Group by assignee [0 API calls, query cache]
```

Total: 1 API call for entire analysis

### Pattern 3: Create Then Verify

**Best practice:**
```
1. Create 5 new tasks [5 API calls]
2. Show me latest tasks (bypass cache) [1 API call]
```

Total: 6 API calls

**Why bypass cache in step 2:** Cache doesn't auto-update on mutations.

---

## Performance Monitoring

### Check API Stats

```
Show me API statistics
```

**Key metrics:**

**Total Calls:**
- < 100/session = Good
- 100-300/session = Moderate
- > 300/session = High (review usage)

**By Endpoint:**
- `/records/list/` should be ≈ unique tables queried
- High counts = cache not working

**By Table:**
- Identify "hot" tables
- Ensure they're cached

### Measure Response Time

**Fast (cache hit):**
- 5-20 milliseconds
- Instant responses

**Slow (cache miss):**
- 500-2000 milliseconds
- First query to table

**Very slow (> 2 seconds):**
- Large table (10,000+ records)
- Network issues
- SmartSuite API slowness

### Cache Hit Rate

**Calculate:**
```
Cache Hits = Total Queries - API Calls
Hit Rate = Cache Hits / Total Queries * 100%
```

**Target:** > 80% hit rate

**Example:**
```
Total queries: 100
API calls: 15
Cache hits: 85
Hit rate: 85% ✅
```

---

## Common Performance Issues

### Issue 1: Slow Responses

**Symptoms:**
- Queries take 5-10+ seconds
- Claude seems sluggish

**Causes:**
1. Cache disabled or bypassed
2. Large tables (100,000+ records)
3. Too many fields requested
4. Network issues

**Solutions:**
```
1. Verify cache is enabled (default)
2. Request fewer fields
3. Use pagination (smaller limits)
4. Check network connection
```

### Issue 2: High Token Usage

**Symptoms:**
- "Context limit reached" errors
- Conversation ends quickly

**Causes:**
1. Requesting all fields
2. Large record counts
3. Not using TOON format (shouldn't happen)

**Solutions:**
```
1. Request minimal fields only
2. Use smaller limits (10-50 instead of 1000)
3. Start new conversation when needed
```

### Issue 3: Rate Limit Errors

**Symptoms:**
```
Error: 429 Too Many Requests
```

**Causes:**
1. Cache bypassed repeatedly
2. Bulk operations without batching
3. Too many operations in short time

**Solutions:**
```
1. Enable caching (default behavior)
2. Space out bulk operations
3. Check API stats for hot spots
4. Wait 1 minute and retry
```

### Issue 4: Stale Data

**Symptoms:**
- Created records don't appear
- Updates not reflected
- Deleted records still show

**Causes:**
- Querying cached data after mutations

**Solutions:**
```
After create/update/delete:
Show me latest [data] (bypass cache)

Or wait 4 hours for cache to expire naturally
```

---

## Optimization Checklist

### Before Querying

- [ ] Do I know which table I need?
- [ ] Do I know which fields I need?
- [ ] Can I use a filter to narrow results?
- [ ] What's the minimum record count I need?

### During Querying

- [ ] Am I requesting only needed fields?
- [ ] Am I using appropriate limits (10-50)?
- [ ] Am I letting cache work (not bypassing)?
- [ ] Am I filtering at database level?

### After Querying

- [ ] Did I get what I needed?
- [ ] Were results instant (cache hit)?
- [ ] Can I reuse this data for other questions?

### Periodic Review

- [ ] Check API stats weekly
- [ ] Verify cache hit rate > 80%
- [ ] Review high-call tables
- [ ] Identify optimization opportunities

---

## Performance Tips Summary

**Top 10 Performance Tips:**

1. **Let cache work** - Don't bypass unnecessarily
2. **Request minimal fields** - Only what you need
3. **Use small limits** - Start with 10-50 records
4. **Filter early** - At database level
5. **Leverage views** - Reuse configurations
6. **Monitor API stats** - Track usage patterns
7. **Paginate large results** - Don't fetch thousands at once
8. **Batch related queries** - Use same cache
9. **Request fresh data strategically** - Only when needed
10. **Use TOON format** - Automatic 50-60% token savings

**Result:** 75% fewer API calls, 60% token savings, 99% faster responses

---

## Benchmarking

### Typical Performance

**Cache Miss (first query):**
- Time: 500-2000ms
- API calls: 1-5 (pagination)
- Tokens: Normal

**Cache Hit (subsequent queries):**
- Time: 5-20ms (99% faster!)
- API calls: 0
- Tokens: Minimal (TOON format)

### Example Session

**Without optimization:**
```
Query 1: 1000ms, 3 API calls
Query 2: 1000ms, 3 API calls
Query 3: 1000ms, 3 API calls
Total: 3 seconds, 9 API calls
```

**With optimization:**
```
Query 1: 1000ms, 3 API calls (cache miss)
Query 2: 10ms, 0 API calls (cache hit)
Query 3: 10ms, 0 API calls (cache hit)
Total: 1.02 seconds, 3 API calls (66% faster, 66% fewer calls)
```

---

## Related Documentation

- **[Caching Guide](caching-guide.md)** - Deep dive into caching
- **[User Guide](user-guide.md)** - General usage patterns
- **[API Reference: Stats](../api/stats.md)** - API monitoring tools
- **[Troubleshooting Guide](../getting-started/troubleshooting.md)** - Common issues

---

## Need Help?

- [Troubleshooting Guide](../getting-started/troubleshooting.md)
- [GitHub Issues](https://github.com/Grupo-AFAL/smartsuite_mcp_server/issues)
- [GitHub Discussions](https://github.com/Grupo-AFAL/smartsuite_mcp_server/discussions)
