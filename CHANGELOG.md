# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [1.7.0] - 2025-01-15

### Changed
- **Modular cache layer architecture** (v1.7):
  - Split `cache_layer.rb` (1646 lines) into focused modules
  - Organized in dedicated `lib/smartsuite/cache/` directory following Ruby conventions:
    - `SmartSuite::Cache::Layer` (923 lines) - Core caching interface
    - `SmartSuite::Cache::Metadata` (459 lines) - Table registry, schema management, TTL config
    - `SmartSuite::Cache::Performance` (131 lines) - Hit/miss tracking, statistics
    - `SmartSuite::Cache::Migrations` (241 lines) - Schema migrations, data migration helpers
    - `SmartSuite::Cache::Query` (272 lines) - Chainable query builder (previously separate)
  - Uses Ruby module mixins for clean separation of concerns
  - All cache classes properly namespaced under `SmartSuite::Cache` module
  - All methods maintain backward compatibility
  - Easier to navigate, test, and maintain
  - No user-facing changes - internal refactoring only
- **Deferred refactorings**:
  - ResponseFormatter strategy pattern → v2.0 (will align with TOON format migration)
  - FilterBuilder extraction → v1.8 (not critical for v1.7)
  - API module refactoring → v1.8 (large task, deferred)
  - Input validation → v1.8
  - Integration tests → v1.8

### Developer Experience
- Improved code organization for cache layer
- Clear module responsibilities reduce cognitive load
- Foundation for future enhancements

### Notes
- This is a refactoring and polish release with no user-facing changes
- All existing tests pass (84 runs, 401 assertions)
- Cache database format remains unchanged
- No migration required for existing installations

## [1.6.0] - 2025-11-15

### Added
- **Cache performance tracking** (v1.6):
  - New `cache_performance` table tracks hit/miss counts per table
  - In-memory counters with periodic flush (every 100 ops or 5 minutes)
  - Batch database writes for performance
  - Tracks: hit_count, miss_count, last_access_time, record_count, cache_size_bytes
  - `get_cache_performance(table_id:)` method to retrieve stats
  - Hit rate calculation: `(hits / total) * 100`
  - Automatic tracking integrated into record operations
- **Extended `get_api_stats` with cache metrics** (v1.6):
  - New `cache_stats` section in response with:
    - Overall hit/miss counts and hit rate percentage
    - API calls made, saved, and without cache (efficiency metrics)
    - Efficiency ratio: percentage of API calls saved by caching
    - Estimated tokens saved (500 tokens per cache hit)
    - Per-table breakdown with individual hit rates and cache sizes
  - New optional `time_range` parameter:
    - `session`: Statistics for current session only
    - `7d`: Statistics for last 7 days
    - `all`: All-time statistics (default)
  - Time-filtered API call statistics (summary, by_method, by_solution, by_table, by_endpoint)
  - Helps users understand cache effectiveness and optimize performance
- **Improved dynamic table and column naming** (v1.6):
  - SQL cache tables now use human-readable names: `cache_records_{sanitized_name}_{table_id}`
    - Example: `cache_records_customers_tbl_abc123` instead of `cache_records_tbl_abc123`
  - Columns now use field labels instead of cryptic slugs
    - Example: `status` instead of `s7e8c12e98`
    - Falls back to slug if label is missing or invalid
  - Automatic deduplication for duplicate column names (appends `_2`, `_3`, etc.)
  - Applies to new cache tables only (no migration required)
  - Stored in `cache_table_registry` for mapping
  - Makes SQL cache more readable and debuggable
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
- **Enhanced prompt registry with 4 new filter examples** (v1.6):
  - `filter_by_empty_fields`: Example for checking if fields are empty or not empty
  - `filter_by_recent_updates`: Example for filtering records updated within last N days
  - `filter_complex_and_or`: Example for complex filters with multiple AND/OR conditions
  - `filter_overdue_tasks`: Example for filtering overdue tasks using due date fields
  - Each prompt includes complete filter syntax, operator guidance, and cache-awareness notes
  - Provides AI assistants with comprehensive examples of common filter patterns
- **New `refresh_cache` tool** (v1.6):
  - MCP tool to manually refresh (invalidate) cache for specific resources
  - Supports three resource types: 'solutions', 'tables', 'records'
  - Invalidates cache without refetching - data refreshes on next access
  - For 'solutions': Invalidates all solutions cache
  - For 'tables': Invalidates table list cache (optional solution_id parameter)
  - For 'records': Invalidates table records cache (requires table_id parameter)
  - Tracks refresh history via existing cache_stats mechanism
  - Returns structured response with timestamp and confirmation message
  - Useful for forcing fresh data when you know it has changed
- **New `warm_cache` tool** (v1.6):
  - MCP tool to proactively warm (populate) cache for specified tables
  - Auto mode: Automatically selects top N most accessed tables from cache_performance
  - Manual mode: Explicit list of table IDs to warm
  - Skips tables that already have valid cache (no redundant fetching)
  - Fetches and caches all records for each table to improve subsequent query performance
  - Returns progress tracking with summary (total, warmed, skipped, errors)
  - Per-table status: 'warmed', 'skipped', or 'error' with details
  - Useful for pre-loading frequently accessed data during off-peak hours

### Changed
- **Phase 4 refactoring decisions** (v1.6):
  - **Extract common API patterns:** Reviewed and decided to keep current explicit implementations
    - Analysis showed each operation has enough unique logic to justify separate code
    - Current code is clear, maintainable, and well-documented
    - Abstraction would reduce readability without significant DRY benefits
  - **Split cache_layer.rb:** Deferred to v1.7
    - File is well-organized with clear section headers
    - No user-facing benefits, significant refactoring risk
    - Current 1646-line file is manageable with good documentation
  - **Strategy pattern for formatters:** Deferred to v1.7
    - Current implementation works well
    - Consider as part of v2.0 TOON format migration
- **Optimized cache population to use `list_records` exclusively** (v1.6):
  - `fetch_all_records` now uses `hydrated=true` parameter
  - Returns complete data including linked records, users, and reference fields
  - Eliminates need for separate `get_record` API calls
  - Same data as individual record fetches (only missing `deleted_by` field)
  - Simpler code, fewer API calls, lower rate limit usage
  - Documented that `get_record` tool remains available for direct user queries
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

[Unreleased]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/releases/tag/v1.0.0
