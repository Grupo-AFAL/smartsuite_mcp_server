# TOON Format vs Current Approach - Evaluation

**Date:** November 19, 2025
**Context:** Roadmap v2.0 planning - Token optimization strategy
**Decision Required:** Should we implement TOON format or continue with current plain text approach?

---

## Executive Summary

**Recommendation: DEFER TOON implementation, PRIORITIZE mutation response optimization instead.**

TOON would provide marginal benefits (~10-15% additional token savings) while requiring significant implementation effort and creating breaking changes. The highest-impact token optimization opportunity is **reducing mutation operation responses** (50-80% potential savings), which we should tackle first.

---

## Current State Analysis

### What We Have Now

**Plain Text Formatting** (`ResponseFormatter.filter_records_response`)
- Converts JSON to human-readable plain text format
- **Token savings: 30-50% vs JSON** (already implemented)
- Shows "X of Y filtered records (Z total)" for context
- Returns full field values (no truncation)
- Easy for humans and AI to read

**Example Current Output:**
```
✓ Found 15 of 150 total records (plain text)

Record 1:
  id: rec_abc123
  title: High Priority Task
  status: In Progress
  priority: High
  assigned_to: John Doe

Record 2:
  id: rec_def456
  title: Bug Fix
  status: Completed
  priority: Medium
  assigned_to: Jane Smith
```

### What's Missing

**Mutation Response Optimization** (NOT YET IMPLEMENTED)
- `create_record` returns full 2KB+ record object
- `update_record` returns full 2KB+ record object
- `bulk_add_records` returns array of full record objects
- AI only needs: `{success: true, id: "rec_123", message: "Record created"}`
- **Potential savings: 50-80% on mutation operations**

---

## TOON Format Analysis

### What is TOON?

TOON (Token-Oriented Object Notation) is a compact data format designed for LLM inputs.
- Spec: https://github.com/toon-format/toon
- Combines YAML indentation + CSV tabular layout
- Optimized for uniform/tabular data (like SmartSuite records)

### TOON Benefits

✅ **Token Efficiency**
- ~40% fewer tokens vs JSON (benchmarked)
- Best for tabular/uniform data structures
- Lossless encoding (round-trips with JSON)

✅ **Parsing Accuracy**
- 88% structure awareness vs 83% for JSON
- Explicit length declarations help AI models
- Better for structured data extraction

### TOON Limitations

❌ **Not Always Better**
- Deeply nested/non-uniform structures: JSON is better
- Adds 5-10% overhead vs pure CSV for tabular data
- Less human-readable than plain text

❌ **Adoption & Maturity**
- Active development but not mainstream
- TypeScript SDK primary, Ruby support unclear
- Limited production usage examples
- Breaking change for all users

### TOON vs Current Plain Text Comparison

| Metric                     | Current Plain Text | TOON Format   | Delta         |
| -------------------------- | ------------------ | ------------- | ------------- |
| Token savings vs JSON      | 30-50%             | ~40%          | **~10% gain** |
| Human readability          | Excellent          | Good          | -             |
| AI parsing accuracy        | ~83%               | ~88%          | **+5%**       |
| Implementation effort      | Already done       | 2-3 weeks     | -             |
| Breaking change            | No                 | **Yes**       | -             |
| Ruby SDK maturity          | N/A                | Unknown       | -             |
| Best use case              | All data types     | Tabular only  | -             |

**Net benefit: ~10-15% additional token savings, +5% parsing accuracy**
**Cost: 2-3 weeks implementation + breaking changes**

---

## Alternative: Mutation Response Optimization

### Current Problem

Mutation operations return massive responses:

```ruby
# create_record currently returns:
{
  "id" => "rec_abc123",
  "title" => "New Task",
  "status" => "Not Started",
  "priority" => "High",
  "assigned_to" => {...},  # Full user object
  "created_on" => "2025-11-19T...",
  "updated_on" => "2025-11-19T...",
  "first_created" => {...},
  "last_updated" => {...},
  # ... 50+ more fields
  # Total: ~2KB+ JSON
}
```

### Proposed Solution

Return only essential information:

```ruby
# Optimized response:
{
  "success" => true,
  "id" => "rec_abc123",
  "title" => "New Task",
  "operation" => "create",
  "timestamp" => "2025-11-19T21:30:00Z",
  "cached" => true  # Indicates record was added to cache
}
# Total: ~150 bytes JSON
```

### Expected Impact

| Operation          | Current Size | Optimized Size | Savings |
| ------------------ | ------------ | -------------- | ------- |
| `create_record`    | ~2-3KB       | ~150 bytes     | **95%** |
| `update_record`    | ~2-3KB       | ~150 bytes     | **95%** |
| `bulk_add_records` | ~10-50KB     | ~1-2KB         | **90%** |
| `delete_record`    | ~500 bytes   | ~100 bytes     | **80%** |

**Average token savings: 50-80% on all mutation operations**

### Additional Benefits

✅ **Smart cache updates**
- Parse response to update local cache
- No need to invalidate entire table cache
- Maintain cache consistency without refetch

✅ **No breaking changes**
- Add `minimal_response: true` parameter (default: false)
- Gradual migration path for users
- Backward compatible

✅ **Immediate value**
- Implementation: ~3-5 days
- Works with existing plain text format
- Measurable token reduction

---

## Cost-Benefit Analysis

### TOON Format Implementation

**Effort:** 2-3 weeks
- Research Ruby TOON library or implement spec
- Replace ResponseFormatter with TOON encoder
- Update all tool descriptions with TOON examples
- Test with all field types and data structures
- Handle edge cases (nested objects, nulls, etc.)
- Create migration guide for users

**Benefits:**
- ~10-15% additional token savings vs current plain text
- +5% parsing accuracy
- More structured data representation

**Costs:**
- **Breaking change** - all users must update
- Unknown Ruby library maturity
- Reduced human readability
- Not optimal for non-tabular data

**ROI:** Moderate - marginal improvement with high implementation cost

---

### Mutation Response Optimization

**Effort:** 3-5 days
- Add response filtering to RecordOperations methods
- Create `minimal_response` parameter (default: false for backward compat)
- Update cache coordination logic
- Add tests for optimized responses
- Update CHANGELOG and tool descriptions

**Benefits:**
- **50-80% token savings on mutations**
- Smart cache updates (no invalidation needed)
- No breaking changes
- Immediate measurable impact

**Costs:**
- ~3-5 days implementation
- Need to test cache coordination carefully

**ROI:** Very High - massive savings with low implementation cost

---

## Recommendation

### Priority 1: Mutation Response Optimization (Immediate)

**Implement minimal mutation responses with smart cache updates**

Benefits:
- 50-80% token savings on create/update/delete operations
- No breaking changes
- Quick implementation (3-5 days)
- Improves cache efficiency

Timeline: **Complete in 1 week**

### Priority 2: Field Selection Intelligence (Short-term)

**Analyze usage patterns to recommend minimal field selections**

Benefits:
- Help AI/users request only needed fields
- Reduce query response sizes
- Educational for users

Timeline: **2-3 weeks**

### Priority 3: TOON Format (Deferred - Q3 2026)

**Re-evaluate TOON after mutation optimization complete**

Rationale:
- Let TOON mature (better Ruby support)
- Measure actual token usage after mutation optimization
- Assess if additional 10-15% savings worth breaking change
- Consider as part of v3.0 (already has breaking changes planned)

Timeline: **Defer to Q3 2026 (v3.0)**

---

## Implementation Plan: Mutation Response Optimization

### Phase 1: RecordOperations (Days 1-2)

```ruby
# Add to create_record, update_record, etc.
def create_record(table_id, data, minimal_response: false)
  response = api_request(:post, "/applications/#{table_id}/records/", data)

  if minimal_response
    # Smart cache update
    @cache&.update_cached_record(table_id, response['id'], response)

    # Return minimal response
    {
      'success' => true,
      'id' => response['id'],
      'title' => response['title'],
      'operation' => 'create',
      'timestamp' => Time.now.utc.iso8601,
      'cached' => @cache ? true : false
    }
  else
    response  # Backward compatible
  end
end
```

### Phase 2: Tool Descriptions (Day 3)

Update MCP tool schemas:
- Add `minimal_response` parameter to mutation tools
- Document token savings in descriptions
- Provide examples of minimal vs full responses

### Phase 3: Testing (Day 4)

- Unit tests for minimal responses
- Cache update verification
- Backward compatibility tests
- Integration tests with real API

### Phase 4: Documentation (Day 5)

- Update CHANGELOG
- Add migration guide
- Document token savings metrics
- Update roadmap

---

## Success Metrics

### Mutation Response Optimization

**Measurable Goals:**
- [ ] 50-80% token reduction on mutation operations
- [ ] Zero cache invalidations needed after mutations
- [ ] 100% backward compatibility maintained
- [ ] <5 days implementation time

**Tracking:**
- Add to `api_stats` table: response_size_before, response_size_after
- Track token savings per operation type
- Monitor cache hit rate improvement

### Future TOON Evaluation (Q3 2026)

**Re-evaluation Criteria:**
- [ ] Ruby TOON library available with >1k stars
- [ ] Production usage examples in Ruby ecosystem
- [ ] Mutation optimization complete + measured
- [ ] v3.0 breaking changes window available

---

## Conclusion

**Don't implement TOON now.** The juice isn't worth the squeeze:
- Current plain text already saves 30-50% vs JSON
- TOON would add only 10-15% more savings
- Requires breaking changes and significant implementation
- Ruby ecosystem support unclear

**Do implement mutation response optimization:**
- 50-80% savings on create/update/delete operations
- No breaking changes
- Quick implementation (1 week)
- Improves cache efficiency
- Measurable immediate impact

**Defer TOON to v3.0 (Q3 2026):**
- Let format mature
- Combine with other breaking changes
- Re-evaluate after mutation optimization proves value

---

**Next Action:** Update ROADMAP.md to reflect this decision and prioritize mutation response optimization for v2.0.
