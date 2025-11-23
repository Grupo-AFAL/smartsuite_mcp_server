# Response Format Analysis & Standardization Plan

## Current Response Format Patterns

### Pattern 1: Collection Responses ✅ STANDARDIZED
Already using `build_collection_response` from Base module:
```ruby
{
  "solutions" => [...],
  "count" => 10,
  # optional metadata
}
```
**Used by**: list_solutions, list_tables, list_members, search_member

### Pattern 2: Analysis Responses
```ruby
{
  "analysis_date" => "2025-01-16T...",  # ⚠️ should be "timestamp"
  "thresholds" => {...},
  "summary" => {...},
  "inactive_solutions" => [...]
}
```
**Used by**: analyze_solution_usage

### Pattern 3: Cache Operation Responses
```ruby
{
  "refreshed" => "solutions",  # ⚠️ should be "operation" or "status"
  "message" => "...",
  "timestamp" => "2025-01-16T..."
}
```
**Used by**: refresh_cache

### Pattern 4: Cache Status Response
```ruby
{
  "timestamp" => "2025-01-16T...",
  "solutions" => {...},
  "tables" => {...},
  "records" => [...]
}
```
**Used by**: get_cache_status

### Pattern 5: Warm Cache Response
```ruby
{
  "status" => "completed",
  "summary" => {...},
  "results" => [...],
  "timestamp" => "2025-01-16T..."
}
```
**Used by**: (previously warm_cache - now removed)

### Pattern 6: Stats Response
```ruby
{
  "time_range" => "all",  # ⚠️ missing timestamp
  "summary" => {...},
  "by_method" => {...}
}
```
**Used by**: get_stats (ApiStatsTracker)

### Pattern 7: Simple Status Response
```ruby
{
  "status" => "success",  # ⚠️ missing timestamp
  "message" => "..."
}
```
**Used by**: reset_stats

### Pattern 8: Error Response
```ruby
{ "error" => "Cache is disabled" }  # ⚠️ inconsistent format
```
**Used by**: get_cache_status, refresh_cache (when cache disabled)

## Identified Inconsistencies

### 1. Timestamp Field
- ✅ Uses "timestamp": refresh_cache, get_cache_status
- ⚠️  Uses "analysis_date": analyze_solution_usage
- ❌ Missing: get_stats, reset_stats

### 2. Status/Operation Indicator
- ✅ Uses "status": reset_stats
- ⚠️  Uses "refreshed": refresh_cache
- ❌ Missing: analyze_solution_usage, get_stats, get_cache_status

### 3. Error Format
- ⚠️  Simple: `{"error" => "message"}`
- ✅ Structured: `{"status" => "error", "message" => "..."}`

### 4. Message Field
- Present in some, absent in others
- No clear pattern

## Proposed Standardization

### Standard Response Format Guidelines

All MCP tool responses should follow these patterns:

#### 1. Collection Response (Already Standardized)
```ruby
{
  "<collection_name>" => [...],
  "count" => N,
  "timestamp" => "2025-01-16T10:30:45Z",  # ADD
  # optional metadata
}
```

#### 2. Operation Response (mutations, actions)
```ruby
{
  "status" => "success" | "completed" | "no_action",
  "operation" => "refresh" | "warm" | "reset" | "analyze",
  "message" => "Human-readable description",
  "timestamp" => "2025-01-16T10:30:45Z",
  # operation-specific data
}
```

#### 3. Query Response (get/status operations)
```ruby
{
  "timestamp" => "2025-01-16T10:30:45Z",
  # query-specific data
}
```

#### 4. Error Response
```ruby
{
  "status" => "error",
  "error" => "Short error identifier",
  "message" => "Detailed error message",
  "timestamp" => "2025-01-16T10:30:45Z"
}
```

### Required Changes

#### High Priority (Breaking Changes)
1. **analyze_solution_usage**: Rename "analysis_date" → "timestamp"
2. **refresh_cache**: Rename "refreshed" → "operation", add "status" = "success"
3. **get_stats**: Add "timestamp" field
4. **reset_stats**: Add "timestamp" field
5. **Error responses**: Standardize to `{"status" => "error", "error" => "...", "message" => "...", "timestamp" => "..."}`

#### Medium Priority (Additions)

1. **Collection responses**: Add "timestamp" to all build_collection_response calls

### Implementation Strategy

1. Create `SmartSuite::ResponseFormats` module with builders:
   - `success_response(operation, message, data = {})`
   - `error_response(error, message)`
   - `query_response(data)`
   - `collection_response(items, collection_name, **metadata)` # wrapper for Base

2. Update methods to use new builders

3. Add migration notes to CHANGELOG

4. Consider deprecation period vs immediate breaking change

### Benefits

- **Consistency**: All responses follow predictable patterns
- **Debugging**: Timestamps on all responses aid troubleshooting
- **Error handling**: Structured errors easier to parse and handle
- **Documentation**: Clear patterns easier to document
- **Testing**: Standardized format easier to test

### Trade-offs

- **Breaking changes**: Existing code relying on current format will break
- **Migration effort**: Need to update all affected methods
- **Testing overhead**: Need to update tests for new formats

## Recommendation

Given that this is a solo developer project with no published v1.0 yet, **implement breaking changes now** before wider adoption. The v1.8 release is perfect timing for this standardization.
