# SmartSuite MCP Server - Product Roadmap

**Last Updated:** November 15, 2025
**Current Version:** 1.5.0
**Next Release:** 1.6.0 (December 2025)
**Decision Log:** See ROADMAP_DECISIONS.md for detailed analysis and decisions

## Vision

Build the most efficient and developer-friendly MCP server for SmartSuite, with aggressive caching, minimal token usage, and comprehensive API coverage.

---

## Completed Milestones ✅

### v1.0 - Core Foundation (Completed)

- ✅ Basic MCP protocol implementation
- ✅ Core SmartSuite API operations (solutions, tables, records, fields, members, comments, views)
- ✅ API statistics tracking with session support
- ✅ Response filtering (83.8% token reduction)
- ✅ Plain text formatting for records (30-50% savings)
- ✅ Comprehensive test suite
- ✅ Solution usage analysis tools
- ✅ Field type mapping and validation

### v1.5 - SQLite Caching Layer (Completed)

- ✅ Dynamic table creation per SmartSuite table
- ✅ Cache-first record fetching strategy
- ✅ TTL-based cache expiration (4 hour default)
- ✅ Chainable query builder (CacheQuery)
- ✅ Local SQL filtering (no API calls for cached data)
- ✅ Schema evolution support
- ✅ Session-based API tracking in SQLite
- ✅ `bypass_cache` parameter for fresh data

---

## Current Focus 🎯

### v1.6 - Cache Optimization (In Progress)

**Goal:** Improve cache performance and observability

**Note:** Solo developer project - all decisions prioritize immediate value over multi-user migration support

#### Phase 1: Foundation (Week 1)

- [x] **Item 7: Remove old cache format migration code** ⚡ Quick win ✅ COMPLETED
  - ✅ Deleted migration methods from `cache_layer.rb` (~79 lines): `migrate_cache_tables_schema`, `migrate_api_call_log_schema`
  - ✅ Migrated all INTEGER timestamps to TEXT (ISO 8601)
  - ✅ Added `session_id` column to api_call_log CREATE TABLE statement
  - ✅ Documented in CHANGELOG as breaking change for pre-v1.5 users
  - ✅ All tests passing (84 runs, 401 assertions)
  - **Rationale:** Solo project, no migration compatibility needed

- [ ] **Item 1: Rename `cached_table_schemas` → `cache_table_registry`**
  - Update all code references in `cache_layer.rb`
  - ALTER TABLE statement (no data migration, instant rename)
  - Update documentation to clarify distinction from `cached_tables`
  - **Purpose:** Internal registry for dynamic SQL cache tables, not SmartSuite API cache

- [ ] **Item 5: Increase cache TTL to 1 week**
  - Solutions: 24h → 7 days
  - Tables: 12h → 7 days
  - Members: None → 7 days
  - Records: 4h → 12h (configurable per table)
  - Add explicit cache invalidation on structure changes (`add_field`, `update_field`, `delete_field`)
  - Add `get_cache_status` tool to show TTL and expiration times

- [ ] **Item 2: Review cache schema** ✅ Approved as-is
  - Keep current 9-table structure (all serve distinct purposes)
  - No indexes needed at current scale
  - Document schema decisions in architecture docs

#### Phase 2: Observability (Week 2)

- [ ] **Item 8: Add `cache_performance` table**
  - Create table: `table_id`, `hit_count`, `miss_count`, `last_access_time`, `record_count`, `cache_size_bytes`
  - Use in-memory counters with periodic flush (every 100 ops or 5 min)
  - Batch database writes for performance
  - Track: hit/miss counts, last access, record counts, cache size

- [ ] **Item 11: Extend `get_api_stats` with cache metrics**
  - Add `cache_stats` section to existing response
  - Include: hit/miss counts, hit rates, token savings estimate, per-table breakdown
  - Add time range filter: `session`, `7d`, `all`
  - Show efficiency ratio: API calls saved vs actual calls

- [ ] **Item 5: Add `get_cache_status` tool** (related to Item 5)
  - Show status for solutions, tables, records (per table)
  - Display: cached_at, expires_at, time_remaining, record_count
  - Help users understand cache state

#### Phase 3: UX Improvements (Week 3)

- [ ] **Item 4: Improve dynamic table and column naming**
  - SQL tables: `cache_records_{sanitized_name}_{table_id}` (e.g., `cache_records_customers_tbl_abc123`)
  - Columns: Use field labels with slug fallback (e.g., `status` instead of `s7e8c12e98`)
  - Apply to new caches only (no migration required)
  - Store mapping in `cache_table_registry`

- [ ] **Item 9: Improve prompt and tool registry**
  - Better categorization: Group by workspace/table/record operations
  - Enhanced descriptions: Add prescriptive guidance and usage hints
  - Add common patterns and anti-patterns to tool definitions
  - Add 4 new filter examples: empty fields, recent updates, complex AND/OR conditions
  - Make AI context more helpful

- [ ] **Item 6: Add user-triggered cache refresh**
  - New MCP tool: `refresh_cache` (resource, table_id, solution_id)
  - Behavior: Invalidate only (not refetch) - refetch on next access
  - Add favorite tables configuration: `~/.smartsuite_mcp_favorites.json`
  - Allow refresh of frequently-used tables via config
  - Track refresh history in `cache_stats`

- [ ] **Item 10: Implement manual cache warming**
  - New MCP tool: `warm_cache` (tables array or 'auto' for top 5)
  - Strategies: Top N accessed tables, user-specified list
  - Show progress during warming
  - Add simple locking to prevent duplicate warming

#### Phase 4: Refactoring (Week 4)

- [ ] **Item 12: Split `cache_layer.rb` into focused modules**
  - Split 1248 lines → 4 files (~300 lines each):
    - `cache_layer.rb` - Core caching, query interface, TTL management
    - `cache_metadata.rb` - Solutions/tables caching, metadata operations
    - `cache_performance.rb` - Performance tracking, statistics, hit/miss recording
    - `cache_migrations.rb` - Version migrations (will be mostly empty after Item 7)
  - Maintain backward compatibility (public API unchanged)
  - Internal refactor only, no breaking changes

- [ ] **Item 12: Extract common API patterns**
  - Create `CachedApiOperation` module for DRY caching behavior
  - Refactor repetitive cache-check-fetch-cache patterns
  - Single place to fix cache bugs
  - Consistent behavior across all operations

- [ ] **Item 12: Strategy pattern for response formatters** (lower priority)
  - Refactor `response_formatter.rb` to use strategy pattern
  - Extract field-type-specific formatters into separate classes
  - Reduce complexity in `filter_field_structure` method
  - Consider deferring to v1.7 if time constrained

- [ ] **Item 3: Optimize to use `list_records` exclusively** ✅ Tested
  - Finding: `list_records(hydrated: true)` returns full data (only missing `deleted_by` field)
  - Switch cache population to use list endpoint only
  - Document that individual `get_record` calls not needed
  - Simpler code, fewer API calls, lower rate limit usage

#### Medium Priority

- [ ] Optimize SQL queries for large cached datasets
- [ ] Add configurable cache size limits
- [ ] Implement cache compression for large text fields
- [ ] Add cache export/import for backup

#### Low Priority

- [ ] Cache prefetching based on usage patterns
- [ ] Smart cache invalidation (detect which records changed)
- [ ] Multi-level caching (memory + SQLite)

---

## Upcoming Releases 📅

### v2.0 - Performance & Scalability (Q1 2026)

**Goal:** Handle large workspaces efficiently

#### Core Improvements

- [ ] Lazy loading for large record sets (pagination in cache layer)
- [ ] Streaming API for large responses
- [ ] Connection pooling for multiple concurrent requests
- [ ] Query optimization for complex filters
- [ ] Parallel fetching for independent API calls

#### Token Optimization

- [ ] **Replace text response format with TOON format**
  - Migrate from plain text to TOON (Toolkit Oriented Object Notation)
  - TOON spec: https://github.com/toon-format/toon
  - Benefits: Better structured data, improved AI readability, reduced token usage
  - Scope: Replace ResponseFormatter plain text output with TOON format
  - Impact: Breaking change (response format), but more efficient for AI assistants
- [ ] Smart field selection based on usage patterns
- [ ] Automatic response compression
- [ ] Differential updates (only changed fields)
- [ ] Response streaming to reduce memory usage

#### Developer Experience

- [ ] CLI tool for cache management (`smartsuite-cache stats`, `smartsuite-cache clear`)
- [ ] Health check endpoint for monitoring
- [ ] Performance metrics dashboard
- [ ] Debug mode with detailed logging

### v2.1 - Advanced Filtering & Search (Q2 2026)

**Goal:** Richer query capabilities

- [ ] Full-text search across cached records
- [ ] Saved filter templates
- [ ] Filter builder helpers
- [ ] Cross-table queries (JOIN support)
- [ ] Aggregation functions (COUNT, SUM, AVG, etc.)
- [ ] Custom SQL query support for power users

### v2.2 - Real-time Updates (Q2 2026)

**Goal:** Keep cache fresh automatically

- [ ] Webhook support for SmartSuite events
- [ ] Real-time cache invalidation
- [ ] Change notification system
- [ ] Optimistic updates with rollback
- [ ] Conflict resolution for concurrent edits

### v3.0 - Multi-Workspace & Collaboration (Q3 2026)

**Goal:** Support teams and multiple workspaces

- [ ] Multi-workspace configuration
- [ ] Workspace switching
- [ ] Shared cache between team members (Redis option)
- [ ] Role-based access control
- [ ] Audit logging for compliance

---

## Feature Ideas (Backlog) 💡

### High Impact

- [ ] **Bulk operations** - Create/update/delete multiple records in one call
- [ ] **Template system** - Pre-defined table structures and workflows
- [ ] **Data validation** - Client-side validation before API calls
- [ ] **Rate limiting** - Smart throttling to respect SmartSuite limits
- [ ] **Retry logic** - Automatic retry with exponential backoff

### Medium Impact

- [ ] **Export/Import** - Backup and restore tables (CSV, JSON, Excel)
- [ ] **Data migrations** - Move data between solutions/tables
- [ ] **Formula support** - Evaluate formulas client-side
- [ ] **File attachments** - Upload/download file fields
- [ ] **Custom views** - Save and reuse complex queries

### Low Impact

- [ ] **Offline mode** - Work with cached data when API unavailable
- [ ] **Data sync** - Two-way sync between SmartSuite and local cache
- [ ] **GraphQL endpoint** - Alternative API interface
- [ ] **REST API wrapper** - Use as standalone REST API
- [ ] **Python/Node.js SDKs** - Client libraries for popular languages

---

## Technical Debt & Refactoring 🔧

### High Priority

- [ ] Extract caching logic into separate gem/library
- [ ] Improve error messages with actionable suggestions
- [ ] Add input validation for all tool parameters
- [ ] Standardize response formats across all tools
- [ ] Add integration tests with real SmartSuite API

### Medium Priority

- [ ] Refactor ResponseFormatter to use strategy pattern
- [ ] Extract filter building into dedicated module
- [ ] Improve code documentation with YARD
- [ ] Add performance benchmarks
- [ ] Create migration guide for breaking changes

### Low Priority

- [ ] Replace manual JSON parsing with JSON schema validation
- [ ] Add static type checking (Sorbet/RBS)
- [ ] Implement design by contract (pre/post conditions)
- [ ] Add mutation testing for test suite quality

---

## Documentation Improvements 📚

### Immediate

- [ ] Create docs/ directory structure (see DOCUMENTATION_PROPOSAL.md)
- [ ] Split README.md into focused guides
- [ ] Consolidate caching docs into single guide
- [ ] Add video tutorials for common workflows
- [ ] Create troubleshooting guide with FAQs

### Future

- [ ] Interactive API explorer
- [ ] Code examples repository
- [ ] Best practices guide
- [ ] Performance tuning guide
- [ ] Security hardening guide

---

## Community & Ecosystem 🌐

### Phase 1 (Q1 2026)

- [ ] Publish to RubyGems
- [ ] Create GitHub Discussions for community support
- [ ] Set up automated issue labeling
- [ ] Create issue templates for bugs/features
- [ ] Add automated testing on PRs

### Phase 2 (Q2 2026)

- [ ] Create example projects repository
- [ ] Write blog posts about architecture decisions
- [ ] Present at Ruby/MCP conferences
- [ ] Create contributor recognition system
- [ ] Set up Discord/Slack community

### Phase 3 (Q3 2026)

- [ ] Plugin system for custom extensions
- [ ] Community-contributed tools/scripts
- [ ] Integration marketplace
- [ ] Certification program for contributors

---

## Breaking Changes & Migrations ⚠️

### Planned Breaking Changes

**v1.6:**

- **Remove old cache format migration code** - Pre-v1.5 cache schemas no longer auto-migrate
  - **Impact:** Users upgrading from v1.4 or earlier will have cache rebuilt on first use
  - **Action Required:** None - cache rebuilds automatically
  - **Rationale:** Solo developer project, simplifies codebase (~70 lines removed)
  - **Workaround:** If data preservation critical, upgrade to v1.5 first, then v1.6

**v2.0:**

- Change default cache TTL from 4 hours to 1 hour (configurable)
- Require `fields` parameter for all record queries
- Remove deprecated `with_full_structure` parameter
- Change response format for `get_api_stats` (more structured)

**v3.0:**

- Move from single-file config to directory-based config
- Replace environment variables with config file
- Change cache database schema (migration provided)

### Migration Support

- Solo developer project: Breaking changes prioritize simplicity over backward compatibility
- CHANGELOG will document all breaking changes with workarounds
- Cache is disposable - rebuilds automatically when schema changes

---

## Success Metrics 📊

### Performance Targets

- **Cache hit rate:** >80% for metadata queries
- **API call reduction:** >75% vs uncached
- **Token savings:** >60% average per session
- **Response time:** <100ms for cached queries

### Quality Targets

- **Test coverage:** >90%
- **Bug resolution time:** <48 hours for critical, <7 days for non-critical
- **Documentation completeness:** 100% of public APIs documented
- **User satisfaction:** >4.5/5 stars

### Adoption Targets

- **GitHub stars:** 500+ by end of 2026
- **Active users:** 100+ by end of 2026
- **Contributors:** 10+ by end of 2026
- **Integrations:** 5+ tools using this server

---

## Contributing to Roadmap

Have ideas for the roadmap? We'd love to hear them!

1. **Check existing issues** - Your idea might already be tracked
2. **Create a feature request** - Use the feature template
3. **Join the discussion** - Comment on roadmap issues
4. **Vote with reactions** - 👍 features you want to see
5. **Submit a PR** - Implement features yourself!

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

---

## Roadmap Status

| Version | Status         | Target Date | Completion |
| ------- | -------------- | ----------- | ---------- |
| v1.0    | ✅ Released    | Nov 2025    | 100%       |
| v1.5    | ✅ Released    | Nov 2025    | 100%       |
| v1.6    | 🚧 In Progress | Dec 2025    | 15%        |
| v2.0    | 📋 Planned     | Q1 2026     | 0%         |
| v2.1    | 📋 Planned     | Q2 2026     | 0%         |
| v2.2    | 📋 Planned     | Q2 2026     | 0%         |
| v3.0    | 💭 Ideation    | Q3 2026     | 0%         |

---

**Legend:**

- ✅ Completed
- 🚧 In Progress
- 📋 Planned (design started)
- 💭 Ideation (not yet planned)
- ❌ Cancelled/Deprioritized
