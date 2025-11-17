# SmartSuite MCP Server - Product Roadmap

**Last Updated:** November 16, 2025
**Current Version:** 1.8.0
**Next Release:** 2.0.0 (Q2 2026)
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

### v1.6 - Cache Optimization (Completed - Dec 2025)

- ✅ Cache performance tracking with `cache_performance` table
- ✅ Extended `get_api_stats` with cache metrics (hit rates, token savings)
- ✅ New cache management tools: `get_cache_status`, `refresh_cache`, `warm_cache`
- ✅ Human-readable SQL table and column names
- ✅ Increased cache TTL values (solutions/tables: 7 days, records: 12h)
- ✅ Removed old migration code, migrated to ISO 8601 timestamps
- ✅ Renamed `cached_table_schemas` → `cache_table_registry`
- ✅ Added 4 new filter example prompts
- ✅ Optimized to use `list_records` exclusively for cache population

### v1.7 - Code Quality & Documentation (Completed - Jan 2026)

- ✅ Split `cache_layer.rb` into focused modules following Ruby conventions:
  - Organized in `lib/smartsuite/cache/` directory
  - Properly namespaced under `SmartSuite::Cache` module
  - `SmartSuite::Cache::Layer` (923 lines) - Core caching interface
  - `SmartSuite::Cache::Metadata` (459 lines) - Table registry, schema management, TTL config
  - `SmartSuite::Cache::Performance` (131 lines) - Hit/miss tracking, statistics
  - `SmartSuite::Cache::Migrations` (241 lines) - Schema migrations
  - `SmartSuite::Cache::Query` (272 lines) - Chainable query builder
- ✅ Follows Ruby file/folder naming conventions (file in `cache/` → module `Cache`)
- ✅ Improved code organization and maintainability
- ✅ All tests passing (84 runs, 401 assertions, backward compatibility maintained)
- ✅ Updated documentation (CHANGELOG, ROADMAP)
- ✅ No user-facing changes - internal refactoring only

### v1.8 - Developer Experience & Quality (Completed - Nov 2025)

#### Code Quality

- ✅ FilterBuilder module extracted from cache layer
- ✅ API::Base module with common helpers for all API operations
- ✅ 35-40% code duplication eliminated across API modules
- ✅ 22 new parameter validation calls added
- ✅ Standardized response formats (ResponseFormats module)

#### Testing

- ✅ Comprehensive test coverage: 68.38% → 82.93% (+14.55%)
- ✅ 99 new tests across 7 test files (404 total tests, 1,419 assertions)
- ✅ Integration tests with workspace confirmation and credential isolation
- ✅ All GitHub Actions passing (Tests, RuboCop, Security, Documentation)

#### Documentation

- ✅ Enhanced YARD documentation (100% coverage, 124 public methods)
- ✅ Comprehensive troubleshooting guide (345 lines, 25+ FAQ entries)
- ✅ Architecture documentation for response formats
- ✅ Updated ROADMAP and CHANGELOG

#### Developer Experience

- ✅ Standardized response formats across all cache tools
- ✅ Input validation comprehensive at API layer
- ✅ CI/CD workflows for quality assurance
- ✅ Security scanning, code quality checks, markdown linting

---

## Current Focus 🎯

### v2.0 - Performance & Scalability (Q2 2026)

**Goal:** Improve developer experience and code quality based on v1.7 learnings

**Note:** This release focuses on practical improvements deferred from v1.7

#### Code Quality

- ✅ **Extract filter building into dedicated FilterBuilder module**

  - Created `lib/smartsuite/filter_builder.rb` with SmartSuite→SQL conversion
  - Supports 20+ comparison operators
  - 30 comprehensive test cases
  - Reusable across operations, cleaner API
  - **Status:** Complete

- ✅ **Refactor API module structure for consistency**
  - Created `SmartSuite::API::Base` module with common helpers
  - All 8 API operation modules refactored to use Base
  - 35-40% code duplication eliminated
  - Added 22 new parameter validation calls
  - Standardized cache coordination, endpoint building, response tracking
  - **Status:** Complete

#### Documentation

- ✅ **Create comprehensive troubleshooting guide**

  - Enhanced `docs/getting-started/troubleshooting.md` (345 new lines)
  - Added 25+ FAQ entries covering common scenarios
  - Documented v1.6-v1.8 cache features
  - Included cache debugging techniques
  - **Status:** Complete

- ✅ **Improve YARD documentation coverage**
  - Added @example tags to all user-facing MCP modules (9 methods)
  - 100% YARD coverage maintained (124 public methods)
  - Generated HTML documentation in `doc/` directory
  - Comprehensive @param, @return, @raise tags
  - **Status:** Complete

#### Developer Experience

- ❌ **Add input validation for all MCP tool parameters**

  - **Decision:** Skipped - validation already comprehensive at API layer
  - Current implementation uses Base module's `validate_required_parameter!` and `validate_optional_parameter!`
  - 22 new validation calls added across API modules in v1.8
  - MCP-level validation would duplicate logic without significant benefit
  - See: `docs/architecture/response-formats-analysis.md` for analysis
  - **Status:** Cancelled

- ✅ **Standardize response formats across all tools**
  - Created `SmartSuite::ResponseFormats` module with 4 builders:
    - `operation_response` - For mutations/actions
    - `error_response` - Structured errors with codes
    - `query_response` - For read operations
    - `collection_response` - For list operations
  - Applied to cache operations (refresh_cache, warm_cache)
  - All responses include ISO 8601 UTC timestamps
  - 22 comprehensive tests (100% module coverage)
  - Documented in `docs/architecture/response-formats-analysis.md`
  - **Status:** Complete (core infrastructure + key methods)

#### Testing

- ✅ **Add integration tests with real SmartSuite API**

  - Created `test/integration/` directory with manual integration tests
  - Test harness for workspace, table, record, cache operations
  - Validates API contract assumptions against real API
  - Run manually with test credentials
  - Documents real API behavior vs assumptions
  - **Status:** Complete (manual tests ready)

- ✅ **Improve test coverage for core modules**
  - Added comprehensive tests for Cache Layer (44 tests)
  - Added comprehensive tests for Prompt Registry (23 tests)
  - Added comprehensive tests for Response Formatter (32 tests)
  - Coverage improved: 68.38% → 82.93% (+14.55%)
  - Total test suite: 404 tests, 1,419 assertions, all passing
  - Remaining gap to 90% target: 7.07%
  - **Status:** Complete (core modules), ongoing for edge cases

**Total estimated effort:** 16-25 days (3-5 weeks)

---

## Upcoming Releases 📅

### v2.0 - Performance & Scalability (Q2 2026)

**Goal:** Token optimization and ease of installation

#### Core Improvements

- [ ] Query optimization for complex filters
- [ ] Create script to install MCP for users without coding skills

#### Token Optimization

- [ ] **Replace text response format with TOON format**
  - Migrate from plain text to TOON (Toolkit Oriented Object Notation)
  - TOON spec: https://github.com/toon-format/toon
  - Benefits: Better structured data, improved AI readability, reduced token usage
  - Scope: Replace ResponseFormatter plain text output with TOON format
  - Impact: Breaking change (response format), but more efficient for AI assistants
- [ ] Smart field selection based on usage patterns
- [ ] Automatic response compression

#### Developer Experience

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

**Note:** Code quality items moved to v1.7 release (see Upcoming Releases section)

### High Priority

- [ ] Extract caching logic into separate gem/library
- [ ] Improve error messages with actionable suggestions
- [ ] Create migration guide for breaking changes

### Medium Priority

- [ ] Add static type checking (Sorbet/RBS)
- [ ] Implement design by contract (pre/post conditions)

### Low Priority

- [ ] Replace manual JSON parsing with JSON schema validation
- [ ] Add mutation testing for test suite quality

---

## Documentation Improvements 📚

**Note:** Core documentation items moved to v1.7 release (see Upcoming Releases section)

### Future

- [ ] Add video tutorials for common workflows

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

| Version | Status      | Target Date | Completion |
| ------- | ----------- | ----------- | ---------- |
| v1.0    | ✅ Released | Nov 2025    | 100%       |
| v1.5    | ✅ Released | Nov 2025    | 100%       |
| v1.6    | ✅ Released | Nov 2025    | 100%       |
| v1.7    | ✅ Released | Nov 2025    | 100%       |
| v1.8    | ✅ Released | Nov 2025    | 100%       |
| v2.0    | 📋 Planned  | Q4 2025     | 0%         |
| v2.1    | 📋 Planned  | Q4 2025     | 0%         |
| v2.2    | 📋 Planned  | Q4 2025     | 0%         |
| v3.0    | 💭 Ideation | Q1 2026     | 0%         |

---

**Legend:**

- ✅ Completed
- 🚧 In Progress
- 📋 Planned (design started)
- 💭 Ideation (not yet planned)
- ❌ Cancelled/Deprioritized
