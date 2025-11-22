# SmartSuite MCP Server - Product Roadmap

**Last Updated:** November 22, 2025
**Current Version:** 1.9.0
**Next Release:** 2.0.0 (Q1 2026)
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

- ✅ Comprehensive test coverage: 68.38% → 82.93% (+14.55%), then **97.47%** (v2.0)
- ✅ 99 new tests across 7 test files, expanded to **927 tests, 2,799 assertions** (v2.0)
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

### v1.9 - Extended Record Operations (Completed - Nov 2025)

**Goal:** Complete record management API coverage with bulk operations and deleted records support

#### Record Operations

- ✅ **Bulk Operations** - Efficient batch processing for multiple records

  - `bulk_add_records`: Create multiple records in a single API call
  - `bulk_update_records`: Update multiple records at once (each must include 'id' field)
  - `bulk_delete_records`: Soft delete multiple records in one operation
  - Significantly more efficient than individual operations when working with many records

- ✅ **File Operations** - File attachment and URL retrieval

  - `attach_file`: Attach files to records by providing publicly accessible URLs
    - SmartSuite downloads files from provided URLs and attaches them
    - Supports single or multiple files in one operation
    - See `SecureFileAttacher` helper for production-safe file uploads
  - `get_file_url`: Get public URLs for files attached to records (20-year lifetime)
    - Accepts file handle from file/image field values
    - Enables direct file access without additional API calls

- ✅ **Deleted Records Management** - Work with soft-deleted records
  - `list_deleted_records`: List all soft-deleted records from a solution
  - `restore_deleted_record`: Restore deleted records back to tables
  - Support for preview mode to limit returned fields
  - Restored records include "(Restored)" suffix in title

#### Testing & Quality

- ✅ 33 comprehensive tests covering all new operations
  - Parameter validation tests for all required fields
  - Type validation for array/hash parameters
  - API error handling for various HTTP error codes
  - Success case verification with proper HTTP mocking
  - 13 additional tests for SecureFileAttacher helper
- ✅ Total test suite: 498 tests, 1,733 assertions (all passing)
- ✅ Code coverage: 78.22% → **97.47%** (v2.0)
- ✅ Tool count increased from 22 to 29 MCP tools (+7 new record operations)

#### Implementation

- ✅ Added 7 new methods in RecordOperations module (bulk operations, file operations, deleted records)
- ✅ Added 7 new MCP tool schemas in ToolRegistry
- ✅ Added SecureFileAttacher helper class for production-safe file uploads (389 lines)
- ✅ Added server handlers in SmartSuiteServer
- ✅ Full YARD documentation for all new methods
- ✅ Updated CHANGELOG with comprehensive change documentation

### Post v1.9 - Documentation & Bug Fixes (Nov 2025)

**Goal:** Complete SmartDoc documentation and fix critical field format bugs

#### Documentation

- ✅ **SmartDoc format documentation** - Complete rich text field formatting reference
  - Added `docs/smartdoc_examples.md` - All 13 validated content types
  - Added `docs/smartdoc_complete_reference.json` - Complete validated structure
  - Added `docs/smartdoc_data_only.json` - Data-only structure
  - Updated `create_record` and `update_record` tool descriptions with SmartDoc examples
  - Documents correct mark types: `"strong"` for bold, `"em"` for italic
  - Covers: paragraphs, headings, text formatting, lists, code blocks, tables, images, attachments, mentions, links, horizontal rules, callouts, emojis

#### Bug Fixes

- ✅ **Single select field format requirements** - Fixed empty/invisible dropdown options bug

  - Root cause: Fields created with simple strings instead of UUIDs, missing color attributes
  - Fixed 4 fields in "Incidentes de Tecnología" table with proper UUIDs and hex colors
  - Added `docs/reference/single_select_field_format.md` - Comprehensive format reference
  - Updated tool descriptions for `add_field`, `bulk_add_fields`, `update_field` with UUID warnings
  - Required format: `{label, value: UUID, value_color: hex, icon_type: "icon", weight: 1}`
  - Prevention: Clear documentation prevents future occurrences

- ✅ **Cache invalidation cascade** - Fixed stale data after cache refresh

  - `refresh_cache('solutions')` now invalidates solutions → tables → records (full cascade)
  - `refresh_cache('tables', solution_id: 'X')` now invalidates tables → records for that solution
  - Added helper methods for cascading invalidation

- ✅ **Date filter with nested hash values** - Fixed SQLite binding error
  - Added `extract_date_value` helper to handle nested date format
  - Supports both `{"date_mode": "exact_date", "date_mode_value": "2025-11-18"}` and simple strings

---

## Current Focus 🎯

### v2.0 - Token Optimization & Usability (In Progress - Nov 2025)

**Goal:** Massive token savings through mutation response optimization and improved installation experience

**Note:** Based on TOON format analysis (see `docs/analysis/toon_format_evaluation.md`), we're prioritizing mutation response optimization (50-80% savings) over TOON format (10-15% savings). TOON deferred to v3.0.

#### Token Optimization (HIGH PRIORITY) ✅

- ✅ **Optimize mutation operation responses (POST/PUT/DELETE)** - **COMPLETED**

  - **Problem:** Create/update/delete operations return full 2-3KB record objects
  - **Solution:** Return minimal responses: `{success, id, title, operation, timestamp, cached}`
  - **Actual savings:** 50-95% token reduction on all mutation operations
  - **Benefits:**
    - Smart cache updates (parse response to update cache, no invalidation needed)
    - `minimal_response: true` parameter (default) for all 6 mutation operations
    - Backward compatible: set `minimal_response: false` for full responses
  - **Scope:** RecordOperations (create/update/delete/bulk operations)
  - **Implementation details:**
    - `cache_single_record(table_id, record)` upserts individual records to cache
    - `delete_cached_record(table_id, record_id)` removes individual records from cache
    - Cache stays synchronized without table-wide invalidation
  - **BREAKING CHANGE:** Default changed to minimal responses (v2.0)

- [ ] **Smart field selection intelligence** - **2-3 weeks**
  - Analyze usage patterns to recommend minimal field selections
  - Help AI/users request only needed fields
  - Reduce query response sizes
  - Educational tooltips/warnings for large field requests

#### Usability ✅

- ✅ **Installation script for non-technical users** - **COMPLETED**

  - Automated installation scripts for macOS/Linux (`install.sh`) and Windows (`install.ps1`)
  - One-liner bootstrap scripts for zero-friction installation
  - Automatic Ruby installation via Homebrew (macOS) or WinGet (Windows)
  - Claude Desktop configuration with proper JSON formatting
  - Interactive prompts for SmartSuite API credentials

- Convert UTC timestamps to local time in logs and reports

#### Performance

- [ ] **Query optimization for complex filters** - **1-2 weeks**
  - Optimize SQL query generation for complex filter combinations
  - Add query plan analysis
  - Index recommendations for frequently queried fields

#### Testing & Quality ✅

- ✅ **Test coverage:** 97.47% (927 tests, 2,799 assertions) - **Exceeded 90% target**
- ✅ **Cache::Schema module** - Centralized SQLite table schema definitions
- ✅ **SmartSuite::Paths module** - Centralized path management for test isolation

**Remaining effort:** 2-3 weeks (smart field selection + query optimization)

---

## Upcoming Releases 📅

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

### v3.0 - Multi-Workspace & Breaking Changes (Q3 2026)

**Goal:** Support teams, multiple workspaces, and complete token optimization (including TOON format)

**Note:** This is a breaking changes release - opportunity to implement TOON format and other improvements deferred from v2.0

#### Token Optimization (DEFERRED FROM v2.0)

- [ ] **TOON format for response formatting** - **2-3 weeks**
  - **Decision:** Deferred from v2.0 after mutation optimization proves value
  - **Rationale:** Current plain text saves 30-50% vs JSON. TOON adds ~10-15% more but requires breaking changes
  - Migrate from plain text to TOON (Toolkit Oriented Object Notation)
  - TOON spec: https://github.com/toon-format/toon
  - Expected benefits: +10-15% token savings, +5% parsing accuracy vs plain text
  - Best for tabular/uniform data (SmartSuite records are ideal)
  - **Prerequisites:**
    - Mutation response optimization complete (v2.0)
    - Measure actual token usage post-v2.0
    - Ruby TOON library mature (>1k stars)
    - Production usage examples available
  - **Impact:** Breaking change - all response formats change
  - **Migration:** Provide conversion guide, example responses
  - **See:** `docs/analysis/toon_format_evaluation.md` for detailed cost-benefit analysis

#### Multi-Workspace Support

- [ ] Multi-workspace configuration
- [ ] Workspace switching
- [ ] Shared cache between team members (Redis option)
- [ ] Role-based access control
- [ ] Audit logging for compliance

#### Other Breaking Changes

- [ ] Move from environment variables to config file
- [ ] Change cache database schema (migration provided)
- [ ] Require `fields` parameter for all record queries (remove default)
- [ ] Remove deprecated parameters and methods

---

## Feature Ideas (Backlog) 💡

### High Impact

- [ ] **Template system** - Pre-defined table structures and workflows
- [ ] **Data validation** - Client-side validation before API calls
- [ ] **Rate limiting** - Smart throttling to respect SmartSuite limits
- [ ] **Retry logic** - Automatic retry with exponential backoff

### Medium Impact

- [ ] **Export/Import** - Backup and restore tables (CSV, JSON, Excel)
- [ ] **Data migrations** - Move data between solutions/tables
- [ ] **Formula support** - Evaluate formulas client-side
- [ ] **File upload** - Upload files to file/image fields (download via `get_file_url` completed in v1.9)
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

| Version | Status         | Target Date | Completion |
| ------- | -------------- | ----------- | ---------- |
| v1.0    | ✅ Released    | Nov 2025    | 100%       |
| v1.5    | ✅ Released    | Nov 2025    | 100%       |
| v1.6    | ✅ Released    | Nov 2025    | 100%       |
| v1.7    | ✅ Released    | Nov 2025    | 100%       |
| v1.8    | ✅ Released    | Nov 2025    | 100%       |
| v1.9    | ✅ Released    | Nov 2025    | 100%       |
| v2.0    | 🚧 In Progress | Nov 2025    | 80%        |
| v2.1    | 📋 Planned     | Q2 2026     | 0%         |
| v2.2    | 📋 Planned     | Q2 2026     | 0%         |
| v3.0    | 📋 Planned     | Q3 2026     | 0%         |

---

**Legend:**

- ✅ Completed
- 🚧 In Progress
- 📋 Planned (design started)
- 💭 Ideation (not yet planned)
- ❌ Cancelled/Deprioritized
