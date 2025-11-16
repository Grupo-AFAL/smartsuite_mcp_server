# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **New `get_cache_status` tool** (v1.6):
  - MCP tool to inspect cache state for solutions, tables, and records
  - Shows: cached_at, expires_at, time_remaining_seconds, record_count, is_valid
  - Optional `table_id` parameter to filter status for specific table
  - Helps users understand cache state and plan refreshes
  - Returns structured data for all cached resources or specific table
- **Automatic cache invalidation on structure changes** (v1.6):
  - Field operations now automatically invalidate table cache:
    - `add_field` - Invalidates table structure and records after adding field
    - `bulk_add_fields` - Invalidates after bulk field additions
    - `update_field` - Invalidates after field updates
    - `delete_field` - Invalidates after field deletion
  - Ensures cached data stays consistent with table schema
  - Both table structure metadata and cached records are refreshed on next access
  - Safe-navigation operator (`&.`) ensures no errors when cache disabled

### Changed
- **Increased cache TTL values** for better performance (v1.6):
  - Solutions: 24 hours → **7 days** (rarely change)
  - Tables: 12 hours → **7 days** (schema stable)
  - Records: 4 hours → **12 hours** (configurable per table)
  - Members: No cache → **7 days** (planned, not yet implemented)
  - Rationale: Longer TTL reduces API calls, improves response times
- **Enhanced `invalidate_table_cache` method** (v1.6):
  - Now accepts `structure_changed` parameter (default: true)
  - Invalidates both cached records AND table structure metadata
  - Separate stat tracking for `table_records` and `table_structure` invalidations
  - Gracefully handles cases where cache doesn't exist for a table
- **Renamed** `cached_table_schemas` table to `cache_table_registry` for clarity
  - This table is an internal registry for dynamically-created SQL cache tables, not a cache of SmartSuite table schemas
  - Database will automatically rename table on first run via ALTER TABLE statement
  - No data migration required, only table rename
- **BREAKING**: Timestamp columns now use ISO 8601 TEXT format instead of Unix INTEGER timestamps
  - Affects all internal metadata tables: `cache_table_registry` (formerly `cached_table_schemas`), `cache_ttl_config`, `cache_stats`, `api_call_log`, `api_stats_summary`
  - Database will automatically migrate INTEGER timestamps to TEXT on first run
  - New timestamps written as `2025-11-16T00:58:39Z` (ISO 8601 with UTC)
  - Old migrated timestamps remain as `2025-11-10 20:01:14` (SQLite datetime format, also ISO 8601 compatible)
  - Both formats supported by Ruby's `Time.parse()`

### Removed
- **BREAKING**: Removed old cache format migration code (~79 lines)
  - `migrate_cache_tables_schema` method (migrated cached_solutions/cached_tables from pre-v1.5 format)
  - `migrate_api_call_log_schema` method (added session_id column migration)
  - Users upgrading from v1.4 or earlier: cache will be automatically rebuilt on first use
  - Rationale: Solo developer project, simplifies codebase maintenance

### Fixed
- Stats tracker initialization: Server now uses client's shared stats tracker instance instead of creating separate instance
- `get_api_stats` no longer attempts to convert TEXT timestamps with `Time.at()` (caused TypeError)
- Added `session_id` column to `api_call_log` CREATE TABLE statement (previously added by migration)

### Internal
- All `Time.now.to_i` calls replaced with `Time.now.utc.iso8601` throughout codebase
- Migration detection logic ensures INTEGER timestamps only migrated once
- Test suite updated to access stats tracker through client instance

## [1.5.0] - 2025-11-15

### Added
- SQLite-based caching layer with dynamic table creation per SmartSuite table
- Cache-first record fetching strategy with TTL-based expiration (4 hour default)
- Chainable query builder (CacheQuery) for local SQL filtering
- `bypass_cache` parameter for forcing fresh API data
- Session tracking in API statistics
- Consolidated database: cache + API stats in single `~/.smartsuite_mcp_cache.db` file

### Changed
- `list_records` now requires `fields` parameter (no default "all fields")
- Response format shows "X of Y total records" to help AI make informed pagination decisions
- SmartSuite filters ignored when using cache (all filtering done locally via SQL)

## [1.0.0] - 2025-11-10

### Added
- Initial release
- Core MCP protocol implementation
- SmartSuite API operations: solutions, tables, records, fields, members, comments, views
- API statistics tracking
- Response filtering (83.8% token reduction)
- Plain text formatting for records (30-50% token savings)
- Comprehensive test suite
- Solution usage analysis tools

[Unreleased]: https://github.com/yourusername/smartsuite_mcp/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/yourusername/smartsuite_mcp/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/yourusername/smartsuite_mcp/releases/tag/v1.0.0
