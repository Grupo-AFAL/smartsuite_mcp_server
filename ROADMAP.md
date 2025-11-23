# SmartSuite MCP Server - Product Roadmap

**Last Updated:** November 23, 2025
**Current Version:** 2.0.0 (in progress)
**Next Release:** 2.0.0 (Q4 2025)

## Vision

Build the most efficient and developer-friendly MCP server for SmartSuite, with aggressive caching, minimal token usage, and comprehensive API coverage.

---

## Completed Milestones

| Version | Focus | Key Features |
|---------|-------|--------------|
| v1.0 | Core Foundation | MCP protocol, SmartSuite API operations, API stats tracking, response filtering (83.8% token reduction) |
| v1.5 | SQLite Caching | Dynamic tables, cache-first strategy, TTL expiration (4h default), chainable query builder |
| v1.6 | Cache Optimization | Cache performance tracking, management tools, human-readable SQL names, extended TTLs |
| v1.7 | Code Quality | Split cache_layer.rb into 5 focused modules under `SmartSuite::Cache` namespace |
| v1.8 | Developer Experience | FilterBuilder, API::Base, 97.47% test coverage, comprehensive YARD docs |
| v1.9 | Extended Operations | Bulk ops, file attachment/URLs, deleted records, SecureFileAttacher helper |

**Post v1.9:** SmartDoc documentation, single select field format fix, cache invalidation cascade, date filter fix.

---

## Current Focus

### v2.0 - Token Optimization & TOON Format (In Progress - Nov 2025)

**Goal:** Massive token savings through optimized responses and TOON format

#### Completed

- **Minimal mutation responses** - 50-95% token reduction
  - `minimal_response: true` (default) for all 6 mutation operations
  - Returns: `{success, id, title, operation, timestamp, cached}`
  - Smart cache updates without table-wide invalidation

- **Installation scripts** - One-liner bootstrap for macOS/Linux/Windows
  - Automatic Ruby installation via Homebrew/WinGet
  - Claude Desktop configuration

- **Test coverage:** 97.47% (927 tests, 2,799 assertions)
- **Cache::Schema module** - Centralized SQLite table schema definitions
- **SmartSuite::Paths module** - Centralized path management for test isolation

#### In Progress

- **TOON format** - Token-Oriented Object Notation (~50-60% savings vs JSON)
  - Default format for list operations (records, solutions, tables, members)
  - `format: :toon` (default) or `format: :json` parameter
  - Tabular format eliminates repetitive field names

#### Remaining

- [ ] Smart field selection intelligence (analyze usage patterns)
- [ ] Query optimization for complex filters
- [ ] Convert UTC timestamps to local time

---

## Upcoming Releases

### v2.1 - Advanced Filtering & Search (Q2 2026)

- Full-text search across cached records
- Saved filter templates
- Cross-table queries (JOIN support)
- Aggregation functions (COUNT, SUM, AVG)

### v2.2 - Real-time Updates (Q2 2026)

- Webhook support for SmartSuite events
- Real-time cache invalidation
- Change notification system

### v3.0 - Multi-Workspace & Breaking Changes (Q3 2026)

- Multi-workspace configuration and switching
- Config file (replace environment variables)
- Cache database schema migration
- Remove deprecated parameters

---

## Feature Backlog

### High Impact
- Template system (pre-defined table structures)
- Data validation (client-side before API calls)
- Rate limiting with smart throttling
- Retry logic with exponential backoff

### Medium Impact
- Export/Import (CSV, JSON, Excel)
- Data migrations between solutions
- Custom views (save complex queries)

### Low Impact
- Offline mode
- GraphQL endpoint
- Python/Node.js SDKs

---

## Technical Debt

- [ ] Extract caching logic into separate gem
- [ ] Add static type checking (Sorbet/RBS)
- [ ] Migration guide for breaking changes

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Cache hit rate | >80% for metadata |
| API call reduction | >75% vs uncached |
| Token savings | >60% average per session |
| Response time | <100ms for cached queries |
| Test coverage | >90% (current: 97.47%) |

---

## Roadmap Status

| Version | Status | Target | Completion |
|---------|--------|--------|------------|
| v1.0-1.9 | Released | Nov 2025 | 100% |
| v2.0 | In Progress | Nov 2025 | 85% |
| v2.1 | Planned | Q2 2026 | 0% |
| v2.2 | Planned | Q2 2026 | 0% |
| v3.0 | Planned | Q3 2026 | 0% |

---

**Legend:** ✅ Completed | 🚧 In Progress | 📋 Planned
