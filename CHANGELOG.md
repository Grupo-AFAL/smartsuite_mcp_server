# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Network access requirements documentation** - Added comprehensive documentation of all domains required for installation
  - Lists all external services needed (GitHub, RubyGems, SmartSuite API)
  - Windows-specific domains (WinGet CDN, Microsoft CDN)
  - macOS-specific domains (Homebrew)
  - DNS resolution error troubleshooting with solutions
  - Proxy configuration instructions for corporate environments

### Fixed

- **Install script Ruby version handling** - The installation script now automatically installs Ruby via Homebrew when an outdated version (e.g., macOS system Ruby 2.6) is detected, instead of just showing an error message and exiting
  - Automatically adds Homebrew Ruby to PATH for the current session
  - Persists PATH change to shell profile
  - Verifies installation succeeded before continuing

- **Install script shell detection** - Fixed shell profile detection to properly identify the user's shell and configure PATH correctly
  - Now detects shell from `$SHELL` environment variable instead of checking if config files exist
  - Supports zsh, bash, and fish shells with correct syntax for each
  - Creates shell profile file (e.g., `~/.zshrc`) if it doesn't exist
  - Correctly determines Homebrew path based on CPU architecture (Apple Silicon vs Intel)
  - Displays detected shell and profile path for transparency

- **Windows installer Ruby version handling** - Fixed the same issue on Windows (install.ps1)
  - Now offers to install the latest Ruby via WinGet when an outdated version is detected
  - Verifies installation succeeded before continuing
  - Consolidated duplicate code into a single flow for both missing and outdated Ruby

- **Windows bootstrap script improvements** - Fixed issues with bootstrap.ps1
  - Added "Press any key to exit" on errors so users can read error messages (window was closing immediately when run via `irm | iex`)
  - Added option to install Git automatically via WinGet when not found
  - Improved error handling throughout the script
  - Run install.ps1 with `-ExecutionPolicy Bypass` to avoid policy restrictions

- **Windows install script encoding fix** - Fixed UTF-8 encoding issues in install.ps1
  - Windows PowerShell has issues parsing UTF-8 Unicode characters, causing syntax errors
  - Replaced all Unicode symbols with ASCII alternatives: `[OK]`, `[ERROR]`, `[WARN]`, `[INFO]`
  - Replaced box-drawing characters in banner with ASCII `+`, `-`, `|`

- **Windows Ruby WinGet installation fix** - Fixed Ruby installation via WinGet
  - Now checks `$LASTEXITCODE` to verify WinGet installation actually succeeded
  - Tries multiple package IDs in order: 3.4 (latest stable), 3.3, 3.2, then generic
  - Shows clear error message if no Ruby package can be found

- **Windows Claude Desktop config not written** - Fixed bug where `claude_desktop_config.json` was created but empty
  - PowerShell's `Add-Member` on hashtables doesn't work well with `ConvertTo-Json`
  - Simplified config building using native hashtable syntax
  - Config now correctly contains the SmartSuite MCP server configuration

- **Windows Ruby path in config** - Config now uses full path to Ruby executable
  - Detects Ruby location from PATH or common installation directories
  - Prevents issues when Claude Desktop doesn't inherit the same PATH as the installer
  - Checks common paths: `C:\Ruby34-x64\bin\ruby.exe`, etc.

## [2.0.0] - 2025-11-24

### Added

- **Transparent Date Input Interface** - AI can now use simple date strings without worrying about SmartSuite's internal format
  - New `SmartSuite::DateTransformer` module for automatic date format conversion
  - Supported input formats:
    - Date only: `"2025-06-20"` → stored without time component
    - UTC datetime: `"2025-06-20T14:30:00Z"` → stored with time
    - Space format: `"2025-06-20 14:30"` → assumed UTC, stored with time
    - Any timezone: `"2025-06-20T14:30:00-07:00"` → auto-converted to UTC
  - Automatically infers `include_time` flag from input format
  - Integrated into `create_record`, `update_record`, `bulk_add_records`, `bulk_update_records`
  - Updated tool descriptions with date handling examples
  - New documentation: `docs/guides/date-handling.md`
  - New test suite: `test/smartsuite/test_date_transformer.rb` with 30 tests

- **UTC to Local Time Conversion** - Automatic conversion of timestamps for user-friendly display
  - New `SmartSuite::DateFormatter` module for timestamp conversion
  - **Automatic timezone detection from SmartSuite user profile** on server startup
    - `SmartSuiteClient.configure_user_timezone` fetches the logged-in user's timezone
    - Ensures dates display consistently with what the user sees in the SmartSuite UI
  - **Named timezone support** (e.g., `America/Mexico_City`, `Europe/London`)
    - Properly handles DST transitions (e.g., -0700 PDT vs -0800 PST)
    - Uses Ruby's TZ environment variable technique for timezone conversion
    - `DateFormatter.named_timezone?` helper to detect named timezone format
  - **Smart midnight detection** to work around SmartSuite API bug where `include_time` is always `false` for `duedatefield` and `daterangefield` types:
    - Non-midnight UTC timestamps are always treated as datetime (have time component)
    - Midnight UTC timestamps trust the `include_time` flag
    - This ensures date-only fields display correctly while datetime fields convert timezone
  - Properly handles SmartSuite's `include_time` flag to distinguish date-only vs datetime fields:
    - **Date-only fields** (`include_time: false`): Return calendar date without timezone conversion (e.g., "Feb 1" stays "Feb 1" regardless of timezone)
    - **Datetime fields** (`include_time: true`): Convert UTC to local timezone (e.g., "11:15 UTC" → "03:15 PST")
  - Configurable timezone via multiple methods (in priority order):
    1. Automatic from SmartSuite user profile (on server startup)
    2. Programmatic: `SmartSuite::DateFormatter.timezone = 'America/Mexico_City'` or `'-0500'`
    3. Environment variable: `SMARTSUITE_TIMEZONE=America/New_York` or `+0530`
    4. System TZ variable: Ruby respects standard `TZ` environment variable
    5. System default: Uses operating system's local timezone
  - Special timezone values:
    - `:utc` - Keep timestamps in UTC (no conversion)
    - `:local` or `:system` - Use system timezone
  - Cache layer updated to store and retrieve `include_time` metadata for all date fields:
    - `datefield`: Added `_include_time` column
    - `daterangefield`: Added `_from_include_time` and `_to_include_time` columns
    - `duedatefield`: Added `_from_include_time` and `_to_include_time` columns
  - Multi-column date field reconstruction for `duedatefield` and `daterangefield`:
    - Displays both `from_date` and `to_date` values
    - Includes `is_overdue` and `is_completed` flags for due date fields
  - `DateFormatter.convert_all` recursively converts timestamps in complex structures
  - `DateFormatter.timezone_info` returns current timezone configuration details with type indicator
  - `DateFormatter.midnight_utc?` helper for smart date-only detection
  - Integrated into `ResponseFormatter.truncate_value` for automatic conversion in all record responses
  - MemberOperations updated to include `timezone` field in member data (matching SmartSuite API field name)
  - New test suite: `test/smartsuite/test_date_formatter.rb` with 50 tests

- **Unified Logging System** - Consolidated all logging into `SmartSuite::Logger` class
  - Single log file: `~/.smartsuite_mcp.log` (production), `~/.smartsuite_mcp_test.log` (test)
  - Replaced multiple logging mechanisms (metrics log, query logger, stderr)
  - Multiple log levels: DEBUG, INFO, WARN, ERROR
  - Log categories: API, DB, CACHE, S3, SERVER, METRIC with color coding
  - ANSI color support (configurable via `colors_enabled`)
  - Daily log rotation
  - Environment variable configuration:
    - `SMARTSUITE_LOG_LEVEL`: Set log level (debug, info, warn, error)
    - `SMARTSUITE_LOG_STDERR`: Set to 'true' to also output to stderr
  - Removed `QueryLogger` class (all code now uses `SmartSuite::Logger` directly)
  - `log_metric` method in HttpClient preserved for API module compatibility

- **Aggressive Caching Strategy** - Consistent cache-first approach across all operations
  - `list_solutions_by_owner`: Now uses cache-first strategy, caches full solution data including permissions
  - `get_table`: Now caches table structure after API fetch for subsequent requests
  - `get_record`: Uses aggressive caching - fetches ALL records on cache miss, then returns requested record
  - `list_deleted_records`: New cache layer for deleted records (stored separately from active records)
    - Returns only `id` and `title` by default for token efficiency
    - New `full_data` parameter to get all fields when needed
    - Replaced `preview` parameter with `full_data` (inverted logic)
  - New `cached_deleted_records` table in SQLite cache schema
  - New cache methods: `cache_deleted_records`, `get_cached_deleted_records`, `deleted_records_cache_valid?`, `invalidate_deleted_records_cache`
  - New helper method `cache_single_table` for individual table caching
  - Refactored `insert_table_row` helper to reduce code duplication

- **TOON format is now default for all list tools** - Standardized token-optimized output across all listing operations
  - TOON (Token-Oriented Object Notation) is now the **default format** for ALL list operations
  - Provides ~50-60% token savings compared to JSON for structured data
  - Uses tabular format for uniform arrays, reducing repetitive field names
  - **Simplified format options**: Only `:toon` (default) and `:json` - removed `:plain_text` format
  - New `format` parameter added to all list tools:
    - `list_records`: `:toon` (default) or `:json`
    - `list_solutions`: `:toon` (default) or `:json`
    - `list_tables`: `:toon` (default) or `:json`
    - `list_members`: `:toon` (default) or `:json`
    - `list_teams`: `:toon` (default) or `:json`
    - `list_solutions_by_owner`: `:toon` (default) or `:json`
    - `search_member`: `:toon` (default) or `:json`
    - `list_comments`: `:toon` (default) or `:json`
    - `list_deleted_records`: `:toon` (default) or `:json`
    - `get_view_records`: `:toon` (default) or `:json`
  - Mutation operations also support format parameter (used when `minimal_response: false`):
    - `create_record`: `:toon` (default) or `:json`
    - `update_record`: `:toon` (default) or `:json`
    - `delete_record`: `:toon` (default) or `:json`
    - `bulk_add_records`: `:toon` (default) or `:json`
    - `bulk_update_records`: `:toon` (default) or `:json`
    - `bulk_delete_records`: `:toon` (default) or `:json`
  - `ToonFormatter` module (`lib/smartsuite/formatters/toon_formatter.rb`) with specialized formatters:
    - `format_records` - Format record lists with counts header
    - `format_record` - Format single record
    - `format_solutions`, `format_tables`, `format_members` - Specialized formatters
    - `format` - Generic TOON encoding for any data
  - Tool schemas updated with `format` parameter enum
  - Internal methods that require hash responses use `:json` format internally
  - Server properly handles string responses (TOON) without re-encoding as JSON

- **AWS profile support for S3 credentials** - `SMARTSUITE_AWS_PROFILE` environment variable for credential isolation
  - Recommended approach for security: use dedicated AWS profile instead of shared environment variables
  - Profile references credentials in `~/.aws/credentials` file
  - Prevents other programs from accidentally using SmartSuite S3 bucket credentials

- **S3 operation logging** - All S3 actions now log to `~/.smartsuite_mcp.log` via unified logger
  - Consistent logging alongside API and cache operations
  - Blue color coding for S3 operations in terminal
  - Actions logged: UPLOAD, UPLOAD_COMPLETE, PRESIGN, ATTACH, ATTACH_COMPLETE, WAIT, CLEANUP, DELETE

- **Transparent local file attachment support** - `attach_file` tool now automatically handles local file paths
  - Detects whether inputs are URLs or local file paths
  - URLs are passed directly to SmartSuite API (existing behavior)
  - Local files are automatically uploaded to S3 via `SecureFileAttacher`, then attached via temporary URLs
  - Supports mixing URLs and local paths in the same request
  - Requires `SMARTSUITE_S3_BUCKET` environment variable for local file uploads
  - AWS credentials can be provided via environment variables or IAM role
  - Lazy-loads `aws-sdk-s3` dependency only when local files are used

- **Test coverage for field_operations.rb** - 24 new tests covering all field CRUD operations
  - Tests for `add_field`, `bulk_add_fields`, `update_field`, `delete_field`
  - Parameter validation tests
  - Cache invalidation verification tests

- **Test coverage for view_operations.rb** - 15 new tests covering view/report operations
  - Tests for `get_view_records` and `create_view`
  - All view modes tested (grid, map, calendar, kanban, gallery, timeline, gantt)
  - Optional parameter handling tests

- **SmartSuite::Paths module** - Centralized path management for database and log files
  - Single source of truth for test mode detection (`SMARTSUITE_TEST_MODE` environment variable)
  - Provides `database_path` and `metrics_log_path` methods with automatic test isolation
  - Ensures tests never write to production database or log files

- **SmartSuite::Cache::Schema module** - Centralized SQLite table schema definitions
  - Single source of truth for all table CREATE statements
  - Eliminates duplication between `Cache::Layer` and `ApiStatsTracker`
  - Methods: `api_stats_tables_sql`, `cache_registry_tables_sql`, `cached_data_tables_sql`, `all_metadata_tables_sql`
  - Both modules now use Schema for consistent table definitions

- **aws-sdk-s3 test dependency** - Added optional dependency for testing SecureFileAttacher
  - Uses AWS SDK's built-in stubbing (`stub_responses: true`) for mocking without real credentials
  - Enables comprehensive testing of S3-based file attachment functionality

- **Teams caching with SQLite** - Implemented cache-first strategy for team operations, consistent with members, tables and solutions caching
  - Added `cached_teams` SQLite table for persistent team caching (7-day TTL)
  - Added `cache_teams`, `get_cached_teams`, `get_cached_team`, `teams_cache_valid?`, and `invalidate_teams_cache` methods to cache layer
  - Updated `list_teams` and `get_team` to use cache-first strategy with automatic fallback to API
  - Added `teams` resource to `refresh_cache` tool for manual cache invalidation
  - Added teams section to `get_cache_status` output for visibility into cache state
  - **Token optimization**: `list_teams` returns `member_count` instead of full member IDs array (significant token savings)
  - **Enriched get_team response**: `get_team` now returns member details (id, email, full_name) instead of just member IDs

- **Deleted member filtering** - By default, soft-deleted members (those with `deleted_date` set) are filtered out from list_members and search_member results
  - Added `include_inactive` parameter to `list_members` tool to optionally include deleted members
  - Added `include_inactive` parameter to `search_member` tool to optionally include deleted members
  - Added `deleted_date` column to `cached_members` table with migration for existing databases
  - Cache layer filters by `deleted_date` in SQL for efficiency
  - Status field clarified: 1=active, 4=invited (pending), 2=unknown
  - Members with `deleted_date` set are hidden from UI and filtered by default

- **Search results sorted by match quality** - `search_member` now returns results sorted by match score (best matches first)
  - Added `match_score` method to FuzzyMatcher for calculating match quality
  - Exact matches rank highest, followed by substring matches, then fuzzy matches
  - Improves usability by showing most relevant results at the top

- **Consistent fuzzy matching across cache/API paths** - `search_member` now uses FuzzyMatcher consistently
  - Both cached and non-cached search paths use `FuzzyMatcher.match?` for name matching
  - Previously, cache path used fuzzy matching while API path used substring matching
  - Users will get identical search results regardless of cache hit/miss state

- **Member caching with SQLite** - Implemented cache-first strategy for member operations, consistent with tables and solutions caching
  - Added `cached_members` SQLite table for persistent member caching (7-day TTL)
  - Added `cache_members`, `get_cached_members`, `members_cache_valid?`, and `invalidate_members_cache` methods to cache layer
  - Updated `list_members` and `search_member` to use cache-first strategy with automatic fallback to API
  - Added `members` resource to `refresh_cache` tool for manual cache invalidation
  - Added members section to `get_cache_status` output for visibility into cache state
  - Caching is transparent: first API call populates cache, subsequent calls use cached data
  - Supports fuzzy search filtering on cached data for `search_member`

- **Documentation: Local Verification** - Updated Git Workflow in `GEMINI.md` to explicitly require local RuboCop, Changelog, and Markdown Lint checks before creating PRs.

- **Refactor: Simplify MemberOperations** - Extracted private helper methods to reduce complexity and duplication
  - `format_member_list`: Centralized logic for formatting member API responses
  - `fetch_solution_member_ids`: Encapsulated complex permission traversal for solution filtering
  - `match_member?`: Isolated search logic for member queries
  - Reduced method complexity and improved readability in `list_members` and `search_member`

- **Documentation: Git Workflow** - Added comprehensive Git workflow guidelines to `GEMINI.md`
  - Explicitly prohibits agent from merging Pull Requests
  - mandates CI checks verification before requesting review
  - Defines clear steps for branching, committing, and verifying changes
  - Establishes standard branch naming conventions (`feature/`, `fix/`, `refactor/`, etc.)

- **SmartDoc format documentation and examples** - Added comprehensive documentation for rich text field formatting with validated examples
  - Added `docs/smartdoc_examples.md` - Complete SmartDoc format reference with all 13 validated content types
  - Added `docs/smartdoc_complete_reference.json` - Complete validated structure from actual SmartSuite record
  - Added `docs/smartdoc_data_only.json` - Data-only structure for easier analysis
  - Updated `create_record` tool description with SmartDoc quick reference and examples
  - Updated `update_record` tool description with SmartDoc quick reference and examples
  - Documents correct mark types: `"strong"` for bold (NOT "bold"), `"em"` for italic (NOT "italic")
  - Includes examples for: paragraphs, headings, text formatting (bold, italic, underline, strikethrough, colors, highlights), lists (bullet, ordered, checklist), code blocks, tables, images, attachments, mentions (records and members), links, horizontal rules, callouts, and emojis
  - Teaches AI to generate proper TipTap/ProseMirror structure instead of HTML for rich text fields
  - Enables Claude to create/update SmartSuite records with properly formatted rich text content

- **Mutation response optimization** - Major token savings for create/update/delete operations (50-95% reduction)
  - Added `minimal_response` parameter (default: true) to all 6 mutation operations
  - **Token savings by operation**:
    - `create_record`: 95% reduction (2-3KB → ~150 bytes)
    - `update_record`: 95% reduction (2-3KB → ~150 bytes)
    - `delete_record`: 80% reduction (2-3KB → ~200 bytes)
    - `bulk_add_records`: 90% reduction per record
    - `bulk_update_records`: 90% reduction per record
    - `bulk_delete_records`: 80% reduction per record
  - **Smart cache coordination**: Mutations update cache with full API response while returning minimal response to user
    - Cache stays synchronized automatically without table-wide invalidation
    - New `cache_single_record(table_id, record)` method upserts individual records to cache
    - New `delete_cached_record(table_id, record_id)` method removes individual records from cache
    - Cache TTL preserved (12 hours default) on upsert operations
  - **Minimal response format**: Returns only essential fields instead of full record
    ```ruby
    {
      'success' => true,
      'id' => 'rec_abc123',
      'title' => 'Record Title',
      'operation' => 'create',  # or 'update', 'delete'
      'timestamp' => '2025-11-19T12:34:56Z',
      'cached' => true
    }
    ```
  - **Full response option**: Set `minimal_response: false` for backward compatibility (returns complete record)
  - **Implementation details**:
    - Updated 6 methods in `RecordOperations` module (`lib/smartsuite/api/record_operations.rb`): lines 327-593
    - Added 2 cache methods in `Cache::Layer` (`lib/smartsuite/cache/layer.rb`): lines 606-657
    - Updated 6 server handlers in `SmartSuiteServer` (`smartsuite_server.rb`): lines 204-240
    - Updated 6 MCP tool schemas in `ToolRegistry` (`lib/smartsuite/mcp/tool_registry.rb`): lines 358-495
  - **Tests**: All 513 tests passing with backward compatibility verified
  - **BREAKING CHANGE**: Default behavior changed to minimal responses (v2.0)
    - Previous versions returned full responses by default
    - To get full responses, explicitly pass `minimal_response: false`
    - Migrations from v1.x to v2.x require updating code expecting full responses

### Changed

- **Unified logging replaces separate log files** - Consolidated logging infrastructure
  - `~/.smartsuite_mcp_metrics.log` → `~/.smartsuite_mcp.log` (production)
  - `~/.smartsuite_mcp_queries.log` → `~/.smartsuite_mcp.log` (production)
  - Single log file simplifies debugging and reduces disk I/O
  - All logging categories (API, DB, CACHE, S3, SERVER, METRIC) now in one file
  - Server no longer creates separate metrics_log file handle

- **Updated design-decisions.md to reflect current architecture** - Updated two outdated sections
  - Section 3: Changed from "Plain Text Responses" to "TOON Format Responses" with implementation details
  - Section 11: Changed from "Ruby Standard Library Only (No Gems)" to "Minimal Dependencies (Essential Gems Only)"
  - Updated summary principles to reflect TOON format and minimal gems (sqlite3, toon-ruby)

- **Updated all documentation to show TOON format** - Replaced plain text references with TOON format
  - API docs: README.md, records.md, workspace.md, tables.md, members.md, comments.md, views.md
  - Architecture docs: overview.md, mcp-protocol.md, data-flow.md
  - Guides: user-guide.md, caching-guide.md, performance-guide.md

- **Consolidated format parameter definitions in ToolRegistry** - All 16 format parameters now use SCHEMA_FORMAT constant
  - Eliminates duplication and ensures consistent description across all tools
  - Affected tools: list_solutions, list_solutions_by_owner, list_tables, list_records, list_deleted_records, list_members, list_teams, search_member, list_comments, get_view_records, and 6 mutation operations

- **Condensed ROADMAP.md** - Reduced from 497 lines to 141 lines (72% reduction)
  - Collapsed completed milestones (v1.0-v1.9) into a compact summary table
  - Updated v2.0 section to show TOON format as "In Progress" (was incorrectly listed as deferred)
  - Removed verbose Community/Ecosystem phases
  - Simplified Feature Backlog and Technical Debt sections

- **`attach_file` returns structured status object** - Now returns detailed response instead of raw API response
  - Returns: `{success, record_id, attached_count, local_files, url_files, details}`
  - `details` array contains type (local/url), files list, and API result for each batch
  - Previously returned `nil` for local file attachments, raw API response for URLs

- **Extracted cache-first pattern to Base module** - DRY refactoring reducing ~50 lines of duplicate code across API modules
  - Added `with_cache_check` helper method for centralized cache checking with automatic logging
  - Added `extract_items_safely` helper for consistent response normalization (Array vs Hash with items)
  - Added `filter_members_by_status` helper in MemberOperations for consistent active/inactive filtering
  - Updated `workspace_operations.rb`, `table_operations.rb`, and `member_operations.rb` to use new helpers
  - Includes 16 new tests covering the helper methods

- **Refactored cache status methods** - Extracted `get_metadata_cache_status` helper to eliminate code duplication
  - Consolidated 4 nearly-identical methods (`get_solutions_cache_status`, `get_tables_cache_status`, `get_members_cache_status`, `get_teams_cache_status`)
  - Reduced ~80 lines of duplicate code to single 24-line helper method
  - Original methods now delegate to helper with table name parameter

- **Refactored cache invalidation methods** - Extracted `invalidate_simple_cache` helper
  - Consolidated duplicate logic in `invalidate_members_cache` and `invalidate_teams_cache`
  - Single helper method handles DB update, stat recording, and logging

- **Improved `refresh_cache` tool description** - Clarified resource parameter to prevent AI from refreshing entire workspace when user wants to refresh one solution
  - Added explicit examples: "To refresh ProductEK solution use resource='tables' with solution_id='sol_123', NOT resource='solutions'"
  - Enumerated all 4 use cases: (1) refresh all workspace, (2) refresh one solution, (3) refresh all tables, (4) refresh one table
  - Changed `solution_id` description to say "required when refreshing a specific solution"
  - Prevents confusion where AI would use `resource: "solutions"` (all solutions) instead of `resource: "tables", solution_id: "X"` (one solution)

### Removed

- **`warm_cache` tool** - Removed unused cache warming functionality
  - Tool, server handler, client method, and tests all removed
  - Cache is automatically populated on first table access
  - Use `list_records` with minimal fields to manually pre-populate cache if needed

- **Obsolete documentation files**
  - `RELEASE_CHECKLIST_v1.9.0.md` - Version 1.9 already released
  - `REFACTORING_REPORT.md` - Recommendations already implemented
  - `docs/ROADMAP_RECOMMENDATIONS.md` - Duplicated and outdated content
  - `docs/architecture/response-formats-analysis.md` - Planning doc, recommendations implemented
  - `docs/analysis/toon_format_evaluation.md` - Decision to defer TOON superseded (TOON now implemented)
  - `docs/analysis/` directory - Empty after above deletion

- **Removed `plain_text` format option** - Simplified format parameter to only `:toon` (default) and `:json`
  - `:plain_text` format was removed from all list tools (`list_records`, `list_solutions`, `list_tables`, `list_members`, `list_teams`, `list_solutions_by_owner`)
  - TOON format provides better token savings (~50-60%) than plain_text (~40%)
  - Reduces code complexity by having only two format options
  - Existing code using `format: :plain_text` should switch to `format: :toon` (or remove the parameter to use default)

### Fixed

- **Timezone field name mismatch** - Fixed `configure_user_timezone` to use correct API field name
  - SmartSuite API returns `timezone` (no underscore), not `time_zone`
  - Updated MemberOperations, SmartSuiteClient, and Cache layer to use `timezone`
  - Added `timezone` column to `cached_members` table schema with migration for existing databases
  - **New `SMARTSUITE_USER_EMAIL` environment variable** for reliable timezone detection
    - Set to your SmartSuite email to ensure your timezone is used (not just first member found)
    - Example: `SMARTSUITE_USER_EMAIL=user@example.com`
    - Falls back to first member with timezone if not set or user not found

- **Daterangefield sub-field filtering (.to_date/.from_date)** - Fixed filtering by daterangefield sub-fields like `field_slug.to_date` or `field_slug.from_date`
  - **Root cause**: `Cache::Query.where()` looked for field info using the full slug including `.to_date`/`.from_date` suffix, but field_mapping uses base slugs
  - **Example**: Filtering by `s31437fa81.to_date` would skip the filter because no field with slug `s31437fa81.to_date` exists
  - **Fix**: Extract base field slug for field lookup, but pass full slug to `build_condition` for column selection
  - Now correctly filters daterangefield End dates (uses `_to` column) and Start dates (uses `_from` column)
  - Added regression tests for `.to_date` and `.from_date` sub-field filtering

- **Date-only filter values now convert to UTC range with DST support** - Fixed date filtering to account for timezone differences and daylight saving time
  - **Root cause**: Date-only filters like `"2026-06-15"` were compared directly against UTC timestamps in cache
  - **Example**: Filtering for June 15 in -0700 timezone missed records at 23:30 local time (06:30 UTC next day)
  - **Fix**: `FilterBuilder.convert_to_utc_for_filter` converts date-only strings to UTC start-of-day timestamps
  - **"is" operator**: Now converts date-only values to BETWEEN range covering the full local calendar day
  - **DST-aware offset calculation**: `local_timezone_offset` now accepts a reference date parameter
    - Calculates the correct timezone offset for the specific date being filtered
    - Example: July dates use -0700 (PDT), November dates use -0800 (PST) for US Pacific timezone
    - Fixes issue where filtering July dates in November would use wrong offset

- **Date-only strings preserved in DateFormatter** - Fixed date-only values being incorrectly converted with timezone offset
  - **Root cause**: `DateFormatter.to_local` was attempting timezone conversion on date-only strings
  - **Example**: `2025-01-15` was becoming `2025-01-14` on servers in UTC+ timezones
  - **Fix**: Date-only strings now pass through unchanged (they represent calendar days, not instants)

- **Cache layer `include_time` column matching bug** - Fixed issue where date values were incorrectly stored in `_include_time` columns instead of 0/1 values
  - The `find_matching_value` method now matches `_from_include_time` and `_to_include_time` columns before `_from` and `_to` columns
  - This ensures proper date-only vs datetime display in responses

- **`list_comments` returning null count** - Now correctly calculates count from results array
  - SmartSuite API returns `count: null` in the response
  - Fixed by calculating count from `results.length` before returning

- **update_field API error when params not provided** - `update_field` now automatically adds empty `params: {}` if not provided
  - SmartSuite API requires the `params` object even for simple field renames
  - Previously failed with `400 - {"params":["This field is required."]}`
  - Now users can simply call `update_field(table_id, slug, {"label": "New Name", "field_type": "textareafield"})` without worrying about params

- **Test isolation from production database** - Fixed tests writing to production database instead of test-specific paths
  - Created `SmartSuite::Paths` module (`lib/smartsuite/paths.rb`) as single source of truth for file paths
  - All components now use `SmartSuite::Paths.database_path` and `SmartSuite::Paths.metrics_log_path`
  - In test mode (`SMARTSUITE_TEST_MODE=true`), uses temporary directory with process-specific filenames
  - `ApiStatsTracker` now creates its own tables when used standalone (without `Cache::Layer`)
  - This prevents test data from polluting production cache and statistics at `~/.smartsuite_mcp_cache.db`

- **SQLite custom function return values** - Fixed `fuzzy_match` function not returning values correctly
  - SQLite3 gem requires using `func.result=` to return values from custom functions
  - Block return values were being ignored, causing fuzzy search to always return 0 results
  - This affected `search_member` and `list_solutions` (with name filter) when using cached data

- **Merge conflict resolution** - Resolved merge conflicts between main and feature branches
- **CRITICAL: firstcreated and lastupdated fields not split into separate columns** - Fixed cache schema to properly split timestamp fields into `_on` and `_by` columns
  - **Root cause**: Field types checked for `'firstcreated'` and `'lastupdated'` but actual types are `'firstcreatedfield'` and `'lastupdatedfield'`
  - **Impact**: These fields were stored as JSON text instead of separate queryable columns
  - **Problem**: Couldn't filter by creation/update date or user - filters returned incorrect results
  - **Fix**:
    - Updated `get_field_columns` to match `'firstcreatedfield'` and `'lastupdatedfield'` (lib/smartsuite/cache/metadata.rb:120-129)
    - Updated `extract_field_value` to use column name prefix (lib/smartsuite/cache/layer.rb:423-432)
    - Updated `find_matching_value` to match new column names (lib/smartsuite/cache/layer.rb:329-348)
    - Updated test to use correct field type
  - **New schema**: Creates `first_created_on`, `first_created_by`, `last_updated_on`, `last_updated_by` columns
  - **Migration**: Delete `~/.smartsuite_mcp_cache.db` to recreate with new schema
  - **Result**: Can now filter by creation/update date and user properly
  - All 513 tests passing

- **CRITICAL: Default minimal_response parameter not applied** - Fixed server handlers not properly defaulting to `minimal_response: true`
  - **Root cause**: When MCP tools didn't pass `minimal_response` parameter, `arguments['minimal_response']` was `nil`
  - Server passed `minimal_response: nil` to methods, which Ruby treats as falsy, so methods defaulted to full response
  - **Impact**: v2.0 mutations returned full responses (defeating the purpose) when parameter not explicitly provided
  - **Fix**: Changed all 6 server handlers to check `arguments.key?('minimal_response')` before accessing value
  - Now correctly defaults to `true` when parameter omitted: `arguments.key?('minimal_response') ? arguments['minimal_response'] : true`
  - Applied to: create_record, update_record, delete_record, bulk_add_records, bulk_update_records, bulk_delete_records
  - **Result**: v2.0 now properly returns minimal responses by default, achieving 50-95% token savings
  - All 513 tests passing with proper default behavior

- **CRITICAL: get_record returns wrong record when filtering by ID** - Fixed cache query builder not handling built-in 'id' field
  - **Root cause**: `Cache::Query.where()` only processed fields in table structure, but 'id' is a built-in field not in structure
  - **Impact**: WHERE clause never added to SQL query for 'id' field, causing query to return first record with LIMIT 1
  - **Example**:
    - Requested: Record ID `68f2c7d5c60a17bb05524112` ("Presentación de Comité de TI")
    - Returned: Record ID `6674c77f3636d0b05182235e` ("RPA: CXP Output") - WRONG RECORD
    - SQL generated: `SELECT * FROM cache_records_... LIMIT 1` (NO WHERE CLAUSE!)
    - Expected SQL: `SELECT * FROM cache_records_... WHERE id = ? LIMIT 1`
  - **Fix**: Added special handling for 'id' field before structure lookup in `Cache::Query.where()` (lib/smartsuite/cache/query.rb:78-83)
    ```ruby
    if field_slug_str == 'id'
      @where_clauses << 'id = ?'
      @params << condition
      next
    end
    ```
  - **Testing**: Added comprehensive regression test with 9 assertions covering:
    - Filter by specific ID (returns correct record)
    - Filter by multiple different IDs
    - Filter by non-existent ID (returns empty array)
    - Combined ID + status filter (both conditions applied)
  - **Result**: get_record now returns correct record when filtering by ID
  - All 514 tests passing (added 1 regression test)

- **Single select field format requirements** - Fixed bug where single select fields displayed empty/invisible options in dropdown menus
  - Root cause: Fields were created with simple string values instead of UUIDs, and missing color attributes
  - Issue: Single select fields showed empty space in dropdowns though options appeared in edit view
  - Solution: Updated all choice values to include required attributes:
    - `value`: UUID string (generated with `SecureRandom.uuid`)
    - `value_color`: Hex color code (e.g., "#FF5757") instead of color names
    - `icon_type`: "icon"
    - `weight`: 1
  - Affected table: "Incidentes de Tecnología" (ID: 691d16fe6f3bee01a1c9fca9) in IT Incident Management solution
  - Fixed 4 fields: s_tipoincid, s_impacto01, s_categoria1, s_escalacio
  - Updated tool descriptions for `add_field`, `bulk_add_fields`, `update_field` with UUID requirement warnings
  - Added comprehensive reference documentation: `docs/reference/single_select_field_format.md`
  - Documentation includes: correct vs incorrect examples, common color codes, symptoms, and prevention strategy
- **Cache invalidation cascade** - Fixed bug where refreshing cache for solutions or tables didn't invalidate cached records
  - `refresh_cache('solutions')` now invalidates solutions → tables → records (full cascade)
  - `refresh_cache('tables', solution_id: 'sol_123')` now invalidates tables → records for that solution
  - Added `invalidate_records_for_solution(solution_id)` private helper method
  - Added `get_table_ids_for_solution(solution_id)` private helper method
  - Modified `invalidate_solutions_cache` to cascade through `invalidate_table_list_cache`
  - Modified `invalidate_table_list_cache` to call `invalidate_records_for_solution` first
  - Bug reported: After refreshing cache, subsequent queries returned stale data from cache
  - Added 4 comprehensive tests for cascading invalidation scenarios
  - Fixes issue where `list_records` would return cached data even after `refresh_cache` was called
  - **Improved cache logging** - Fixed missing query logs by using `db_execute` instead of `@db.execute`
    - Changed 5 instances in `cache/layer.rb`: `insert_record` (line 308), `cache_table_records` (line 250), `invalidate_table_cache` (line 520), `cache_valid?` (line 543), `invalidate_records_for_solution` (line 1116)
    - All cache INSERT, DELETE, UPDATE, and SELECT operations now logged to `~/.smartsuite_mcp_queries.log`
    - Makes cache operations visible for debugging and monitoring
- **Date filter with nested hash values** - Fixed SQLite binding error when filtering by date fields with nested value objects
  - Bug: When SmartSuite API sent date filters with nested format like `{"field": "due_date", "comparison": "is_after", "value": {"date_mode": "exact_date", "date_mode_value": "2025-11-18"}}`, FilterBuilder passed the entire hash to Cache::Query which tried to bind it as an SQL parameter, causing "no such bind parameter" SQLite error
  - Fix: Added `extract_date_value` helper method to `FilterBuilder` to extract the actual date string from `value['date_mode_value']` when value is a nested hash
  - Modified `convert_comparison` method to use `extract_date_value` for all date operators: `is_before`, `is_after`, `is_on_or_before`, `is_on_or_after`
  - Maintains backward compatibility with simple date string format (e.g., "2025-11-18")
  - Added 10 comprehensive regression tests in `test/test_filter_builder.rb` to prevent similar bugs:
    - Tests for `extract_date_value` helper with simple string, nested hash, and nil values
    - Tests for all date operators (`is_after`, `is_before`, `is_on_or_after`, `is_on_or_before`) with both nested hash and simple string formats
    - Integration tests for `apply_to_query` with nested date filter and mixed date formats

## [1.9.0] - 2025-11-18

### Added

- **Bulk record operations** - Added 3 new bulk operations for efficient batch processing
  - `bulk_add_records`: Create multiple records in a single API call
  - `bulk_update_records`: Update multiple records in a single API call (each record must include 'id' field)
  - `bulk_delete_records`: Soft delete multiple records in a single API call
  - All bulk operations are more efficient than multiple individual calls when working with many records
  - Implemented in `RecordOperations` module (lines 374-432)
  - Added MCP tool schemas in `ToolRegistry` (lines 294-356)
  - Added server handlers in `SmartSuiteServer` (lines 209-214)

- **File URL retrieval** - Added operation to get public URLs for attached files
  - `get_file_url`: Returns a public URL for a file attachment (20-year lifetime)
  - Accepts file handle from file/image field values
  - Implemented in `RecordOperations` module (lines 434-449)
  - Added MCP tool schema in `ToolRegistry` (lines 357-370)
  - Added server handler in `SmartSuiteServer` (line 215-216)

- **File attachment** - Added operation to attach files to records by URL
  - `attach_file`: Attach files by providing publicly accessible URLs
  - SmartSuite downloads files from provided URLs and attaches them to specified field
  - Supports single or multiple files in one operation
  - Implemented in `RecordOperations` module (lines 492-528)
  - Added MCP tool schema in `ToolRegistry` (lines 441-454)
  - Added server handler in `SmartSuiteServer` (lines 222-228)
  - Added 6 comprehensive tests (success, parameter validation, API error)

- **Secure file attachment helper** - Added `SecureFileAttacher` class for secure local file uploads
  - Addresses security limitation of `attach_file` requiring public URLs
  - Uses AWS S3 with short-lived pre-signed URLs (default: 2 minutes)
  - Automatic file cleanup after SmartSuite fetches files
  - Server-side encryption enabled by default
  - Supports single or multiple file uploads
  - Implemented in `lib/secure_file_attacher.rb` (389 lines)
  - Added 13 comprehensive tests in `test/test_secure_file_attacher.rb`
  - Added complete usage examples in `examples/secure_file_attachment.rb`
  - Added detailed setup guide in `docs/guides/secure-file-attachment.md`
  - Security features:
    - Pre-signed URLs expire in 60-120 seconds
    - Files deleted immediately after SmartSuite fetch
    - Lifecycle policy for failsafe cleanup
    - Minimal IAM permissions required
    - Debug logging support

- **Deleted records management** - Added operations for working with soft-deleted records
  - `list_deleted_records`: List all soft-deleted records from a solution
    - Accepts `preview` parameter to limit returned fields (default: true)
    - Returns records with deletion metadata
  - `restore_deleted_record`: Restore a soft-deleted record back to the table
    - Appends "(Restored)" to the record title
  - Implemented in `RecordOperations` module (lines 451-490)
  - Added MCP tool schemas in `ToolRegistry` (lines 371-406)
  - Added server handlers in `SmartSuiteServer` (lines 217-220)

- **is_exactly operator for JSON array fields** - New operator to check if array contains exactly specified values (no more, no less)
  - **Implementation**: Combines JSON array length check with value presence checks
  - **SQL generation**: `json_array_length(field) = ? AND json_extract(field, '$') LIKE ? AND ...`
  - **Affected field types**: userfield, multipleselectfield, linkedrecordfield
  - **Use case**: Find records where `tags` is exactly `['tag_a', 'tag_b']` (not `['tag_a']` or `['tag_a', 'tag_b', 'tag_c']`)
  - **Example**: `.where(tags: { is_exactly: ['tag_a', 'tag_b'] })`
  - **Testing**: Verified against SmartSuite API for linkedrecordfield and multipleselectfield (2/2 tests pass)
  - **Added in**: `Cache::Query.build_complex_condition` (line 376-383)

- **Fuzzy name search for solutions** - Filter solutions by name with typo tolerance
  - Added `name` parameter to `list_solutions` tool with strong recommendation to use for token optimization
  - Tool description emphasizes using `name` filter to significantly reduce token usage by returning only matching solutions
  - Custom SQLite function `fuzzy_match()` registered for DB-layer filtering
  - Supports partial matches, case-insensitive, accent-insensitive
  - Allows up to 2 character typos using Levenshtein distance
  - Examples: "desarollo" matches "Desarrollos de software", "gestion" matches "Gestión de Proyectos"
  - Implemented in `FuzzyMatcher` module with comprehensive test coverage (19 tests, 57 assertions)
  - Comprehensive accent support tested: all Spanish vowels (á,é,í,ó,ú), special chars (ñ,ü), uppercase, bidirectional matching

### Changed

- **Test helper methods** - Extracted common test patterns to reduce duplication
  - Added `create_client`: Eliminates repeated client instantiation in tests
  - Added `assert_requires_parameter`: DRY pattern for parameter validation tests
  - Added `assert_api_error`: DRY pattern for API error handling tests
  - Applied to 22 new tests for bulk operations, file operations, and deleted records
  - Reduced test file by 55 lines (1,022 → 967 lines, -5.4%)
  - Improved test readability and maintainability

- **Schema constants in ToolRegistry** - Extracted common parameter schemas
  - Added 10 reusable schema constants (SCHEMA_TABLE_ID, SCHEMA_FILE_URLS, etc.)
  - Applied to 7 new record operation tools
  - Eliminates 40 lines of schema duplication
  - Single source of truth for parameter definitions
  - Frozen constants prevent accidental mutation

- **Verified numeric field operators work correctly** - Comprehensive testing confirms all comparison operators match SmartSuite API
  - **Operators tested**: gt, gte, lt, lte, eq (5 operators)
  - **Field types tested**: numberfield, currencyfield, percentfield, ratingfield (4 field types)
  - **Test coverage**: 11 test cases covering all operators across all numeric field types
  - **Result**: 11/11 tests pass - cache returns identical results to SmartSuite API
  - **Operators**:
    - `:gt` → `is_greater_than` → `field > value`
    - `:gte` → `is_equal_or_greater_than` → `field >= value`
    - `:lt` → `is_less_than` → `field < value`
    - `:lte` → `is_equal_or_less_than` → `field <= value`
    - `:eq` → `is_equal_to` → `field = value`

- **Missing documentation files** - Created comprehensive documentation to fix broken links:
  - `docs/getting-started/configuration.md` - Complete environment variable and cache configuration guide
  - `docs/reference/filter-operators.md` - Comprehensive filter operator reference organized by field type
  - `docs/contributing/code-style.md` - Ruby coding standards and style guidelines
  - `docs/contributing/testing.md` - Testing standards and best practices with Minitest
  - `docs/contributing/documentation.md` - Documentation standards and writing guidelines

- **One-liner installation** - Zero-friction installation with a single command:
  - **macOS/Linux**: `curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash`
  - **Windows**: `irm https://raw.githubusercontent.com/.../bootstrap.ps1 | iex`
  - Bootstrap scripts automatically:
    - Clone repository to `~/.smartsuite_mcp`
    - Run the full installation script
    - Handle updates to existing installations
    - No manual git clone required
  - Users just paste one command and enter their API credentials
  - Easiest possible installation experience

- **Automated installation scripts** for non-technical users:
  - **macOS/Linux**: `./install.sh` - Bash-based installer with Homebrew integration
    - Automatic Homebrew installation on macOS (if not present)
    - Automatic Ruby installation via Homebrew on macOS
    - Support for Apple Silicon and Intel Macs
    - Support for jq (if installed) for safer JSON manipulation
  - **Windows**: `.\install.ps1` - PowerShell-based installer for Windows
    - Automatic Ruby installation via WinGet (Windows Package Manager)
    - Works on Windows 10 (version 1809+) and Windows 11
    - Interactive prompt to install Ruby if not present
    - Fallback to manual installation if WinGet unavailable
  - One-command installation process across all platforms
  - Automatic Ruby version checking (3.0+ required)
  - Automatic dependency installation via Bundler
  - Interactive prompts for SmartSuite API credentials
  - Automatic Claude Desktop configuration with proper JSON formatting
  - Backup of existing configuration before making changes
  - Color-coded output for success/error/warning messages
  - Comprehensive error handling and validation
  - True cross-platform auto-installation: macOS, Linux, and Windows

- **Development workflow guidelines** in CLAUDE.md:
  - Feature branch workflow (always create branches before starting work)
  - Branch naming conventions (feature/, fix/, refactor/, docs/)
  - Completion checklist: Documentation, Tests, Code Quality, Linting, Refactoring, GitHub Actions
  - Example completion workflow with all necessary commands
  - Ensures consistent quality and completeness for all future features

- **Cache query sorting** - Added `order(field_slug, direction)` method to Cache::Query
  - Supports ASC/DESC sorting on cached records
  - Enables local sorting without API calls
  - Applied via `apply_sorting_to_query` in RecordOperations

- **get_record cache support** - `get_record` now uses cache-first strategy
  - Only makes API call if record not cached
  - Significant performance improvement for individual record lookups (~100ms → <10ms)
  - Applies SmartDoc HTML extraction to both cached and API responses

- **get_table caching** - Added caching support to `get_table` method
  - Caches table structure with 12-hour TTL
  - Reduces API calls for frequently accessed table metadata

- **SmartDoc HTML extraction** - 60-70% token savings for rich text fields
  - Extract only HTML content from SmartDoc/richtextarea fields
  - SmartDoc fields contain `{data, html, preview, yjsData}` but AI only needs HTML
  - Cache stores complete JSON, but `get_record` and `list_records` return only HTML
  - Added JSON string parsing to handle cached values
  - Reduces token usage by 60-70% for rich text fields (e.g., 100KB JSON → 3-4KB HTML)

- **Color-coded logging** - ANSI color codes for different log types
  - API operations: Cyan
  - Database queries: Green
  - Cache operations: Magenta
  - Errors: Red
  - Easier visual scanning of logs during development

- **Separate test/production logs** - Environment-based log file separation
  - Test logs: `~/.smartsuite_mcp_queries_test.log`
  - Production logs: `~/.smartsuite_mcp_queries.log`
  - Auto-detection based on environment
  - Prevents test noise in production logs

- **README.md** - Completely restructured Quick Start section:
  - **One-liner installation** now featured as primary method (easiest!)
  - Manual clone + script moved to "Alternative" section
  - Removed verbose prerequisites (bootstrap scripts handle git checks)
  - Simplified and streamlined documentation
  - Focus on "paste one command, enter credentials, done"

- **ROADMAP.md** - Updated v2.0 goals to focus on "Token optimization and ease of installation"

### Removed

- **BREAKING: `bypass_cache` parameter removed** - Removed bypass_cache parameter from all operations
  - Rationale: During development, bypass_cache served as an escape valve that masked cache implementation issues instead of fixing root causes
  - Affected methods: `list_records`, `list_tables`, `list_solutions`
  - Migration: Remove any `bypass_cache: true` arguments from tool calls
  - Cache behavior: Cache expires naturally by TTL (4 hours default) - no manual bypass needed
  - If cache issues occur, they should be investigated and fixed rather than bypassed

### Fixed

- **Sort behavior now consistent across cache states** - All sort criteria applied regardless of cache enabled/disabled
  - **Breaking**: Previously, only first sort criterion was applied when cache enabled; now all criteria applied
  - Updated `Cache::Query.order()` to support multiple ORDER BY clauses (appends instead of replacing)
  - Updated `apply_sorting_to_query()` to iterate through all sort criteria, not just first
  - SQL generation now joins multiple ORDER BY clauses: `ORDER BY field1 ASC, field2 DESC`
  - Behavior now consistent: sort parameter works identically whether cache is enabled or disabled

- **Simplified tool descriptions** - Removed cache implementation details from tool registry
  - Tool descriptions now focus on WHAT tools do, not HOW they implement it
  - Removed "cache-first strategy", "SQL WHERE clauses", "zero API cost" from descriptions
  - Removed cache notes from CRUD operations (create/update/delete records, add/update/delete fields)
  - AI and users no longer need to think about caching - parameters just work consistently
  - Cache management tools (get_cache_status, refresh_cache, warm_cache) appropriately keep cache mentions

- **CRITICAL: Fixed cache index creation bug for label-based column names** - Daterangefield and statusfield indexes now use correct column names
  - **Root cause**: Column names are generated from field labels, but index creation was using field slugs
  - **Example**: Field with slug `sf_daterange` and label "Date Range" creates columns `date_range_from` and `date_range_to`, but indexes tried to use `sf_daterange_from` (column doesn't exist → SQL error)
  - **Affected field types**: daterangefield, duedatefield, statusfield, and all other fields with labels different from slugs
  - **Fixed in 3 locations**:
    1. `Cache::Metadata.create_indexes_for_table` (line 269-290): Now uses actual column names from field_mapping instead of regenerating from slug
    2. `Cache::Metadata.handle_schema_evolution` (line 481-514): Fixed dynamic field addition to use correct column names for indexes
    3. `Cache::Layer.extract_field_value` (line 388-400): Fixed to use field label (with slug fallback) matching `get_field_columns` naming
    4. `Cache::Layer.find_matching_value` (line 338-350): Fixed statusfield matching to use label-based column names
  - **Impact**: Tables with daterange, duedate, or status fields can now be cached successfully
  - **Migration**: Restart MCP server and delete `~/.smartsuite_mcp_cache.db` to recreate tables with correct indexes

- **CRITICAL: Fixed duedatefield and daterangefield filtering to match SmartSuite API behavior** - Cache now uses correct column for date comparisons
  - **Root cause**: Cache was using `from_date` column for all comparisons, but SmartSuite API uses `to_date`
  - **Discovery**: Created test record with date range (from: 2025-03-01, to: 2025-03-31) and compared cache vs API filtering results
  - **SmartSuite API behavior** (verified via direct API testing):
    - Standard field (e.g., `due_date`): ALL comparisons use `to_date` column
      - `is_after value`: `to_date > value`
      - `is_on_or_after value`: `to_date >= value`
      - `is_before value`: `to_date < value`
      - `is_on_or_before value`: `to_date <= value`
    - Sub-field filtering (e.g., `due_date.from_date`): Uses specified column
      - `due_date.from_date`: Filters by `from_date` column
      - `due_date.to_date`: Filters by `to_date` column
  - **Previous behavior**: Cache used `from_date` for all date comparisons → returned DIFFERENT results than API
  - **Fixed behavior**: Cache now uses `to_date` by default (matching API), supports sub-field filtering
  - **Example impact**:
    - Record with due_date from 2025-03-01 to 2025-03-31
    - Filter: `is_on_or_after 2025-03-15`
    - **Before fix**: ❌ NOT returned (cache checked `from_date` 2025-03-01 >= 2025-03-15 = false)
    - **After fix**: ✅ RETURNED (cache checks `to_date` 2025-03-31 >= 2025-03-15 = true)
  - **Fixed in**:
    1. `Cache::Query.build_condition` (line 219-251): Added special handling for duedatefield and daterangefield to select `to_date` column for filtering
    2. `Cache::Query.order` (line 74-110): Added special handling for duedatefield and daterangefield to select `to_date` column for sorting
  - **Impact**: Date filtering AND sorting now return identical results whether using cache or API
  - **Migration**: Delete `~/.smartsuite_mcp_cache.db` and restart to rebuild cache with correct filtering and sorting

- **CRITICAL: Fixed is_empty/is_not_empty filtering for JSON array fields** - Cache now correctly handles empty arrays for userfield, multipleselectfield, and linkedrecordfield
  - **Root cause**: Cache was using `IS NULL` / `IS NOT NULL` checks, but SmartSuite API checks if array is empty `[]`
  - **Discovery**: Direct API testing revealed cache returned different results for `assigned_to is_not_empty` filter
  - **SmartSuite API behavior** (verified via direct API testing):
    - `is_empty`: Returns records where array is empty `[]` (NOT just NULL)
    - `is_not_empty`: Returns records where array has at least one element (NOT just NOT NULL)
  - **Affected field types**: userfield, multipleselectfield, linkedrecordfield
  - **Previous behavior**:
    - `is_not_empty`: Returned ALL records with non-NULL values (including empty arrays `[]`) → WRONG
    - `is_empty`: Only returned NULL records (not empty arrays `[]`) → WRONG
  - **Fixed behavior**:
    - `is_not_empty`: `(field IS NOT NULL AND field != '[]')` → Returns only records with elements
    - `is_empty`: `(field IS NULL OR field = '[]')` → Returns only records with no elements
  - **Example impact**:
    - Record with `assigned_to: []` (empty array)
    - Filter: `assigned_to is_not_empty`
    - **Before fix**: ❌ RETURNED (cache checked IS NOT NULL → true for empty array)
    - **After fix**: ✅ NOT returned (cache checks `!= '[]'` → false for empty array)
  - **Fixed in**: `Cache::Query.build_complex_condition` (line 315-336)
  - **Impact**: Array field filtering now returns identical results to SmartSuite API
  - **Comprehensive testing**:
    - Verified against API for statusfield, singleselectfield, multipleselectfield, userfield (7/7 tests pass)
    - Verified all linkedrecordfield operators: has_any_of, has_all_of, has_none_of, is_empty, is_not_empty (8/8 tests pass)

- **CRITICAL: Refactored field type detection to prevent regex pattern matching bugs** - Replaced fragile regex patterns with exact type checking
  - **Root cause**: Field type `linkedrecordfield` contains substrings "text" and "link" which incorrectly matched text field regex `/text|email|phone|link/` BEFORE matching array field pattern
  - **Discovery**: is_empty/is_not_empty tests for linkedrecordfield failed because it was being treated as text field (checking `= ''` instead of `= '[]'`)
  - **Previous behavior**: Used regex patterns to categorize fields → substring matches caused incorrect behavior
  - **Fixed behavior**: Uses whitelist constants with exact type matching → no false matches possible
  - **Changes**:
    - Added `JSON_ARRAY_FIELD_TYPES` constant (line 22-26): `%w[userfield multipleselectfield linkedrecordfield]`
    - Added `TEXT_FIELD_TYPES` constant (line 28-35): `%w[textfield textareafield richtextareafield emailfield phonefield linkfield]`
    - Added `json_array_field?(field_type)` helper method (line 48-50): Exact type checking for JSON arrays
    - Added `text_field?(field_type)` helper method (line 53-55): Exact type checking for text fields
    - Refactored is_empty/is_not_empty to use helper methods instead of regex (line 341-360)
  - **Impact**: Eliminates entire class of bugs related to substring matching in field type detection
  - **Benefits**: More maintainable, more explicit, easier to extend with new field types
  - **Fixed in**: `Cache::Query` (lib/smartsuite/cache/query.rb)

- **SmartDoc HTML extraction from cached records** - Fixed ResponseFormatter not extracting HTML from rich text fields when using cache
  - Cache stores SmartDoc fields as JSON strings, but ResponseFormatter was only detecting Hash objects
  - Added JSON string parsing to `truncate_value` method before SmartDoc detection
  - Now correctly extracts HTML from both direct API responses (Hashes) and cached records (JSON strings)
  - Mirrors the approach used in RecordOperations.process_smartdoc_fields
  - Reduces token usage for rich text fields from ~25k to ~3-4k tokens (87-90% reduction)
  - Added 12 comprehensive tests covering JSON string parsing, SmartDoc detection, and edge cases
  - Fixes issue where list_records returned full TipTap/ProseMirror JSON instead of just HTML content
- **is_empty/is_not_empty filter API rejection** - Fixed SmartSuite API rejecting empty check filters with non-null values
  - Error: `"' is not allowed for the 'is_not_empty' comparison"` (API error 400)
  - SmartSuite API requires `null` value for `is_empty` and `is_not_empty` operators, not empty string
  - Added `sanitize_filter_for_api` method in RecordOperations to clean filters before sending to API
  - Automatically converts empty string or any value to `null` for empty check operators
  - Other filter operators are preserved unchanged
  - Added 4 regression tests to verify sanitization logic
  - Resolves MCP error -32603 when using empty check filters with `bypass_cache: true`
- **SQLite type coercion errors** - Fixed "can't convert String into an exact number" errors in cache operations
  - **COUNT() fix**: SQLite COUNT() returns strings in some configurations, calling `.positive?` on String fails
    - Fixed 4 occurrences in cache/layer.rb: lines 531, 716, 916, 924
    - Now converts to integer before calling `.positive?`: `result['count'].to_i.positive?`
  - **Time.at() fix**: Removed incorrect `Time.at()` calls in `get_cached_table_list` (lines 888, 889, 892)
    - Database stores ISO 8601 strings, not Unix timestamps
    - `Time.at()` expects numeric timestamps, causing TypeError with string values
    - Now returns ISO 8601 strings directly without conversion
  - Resolves MCP error -32603 when calling list_tables with solution_id parameter
- **list_solutions cache bypass** - Fixed list_solutions to use cache even when fields parameter is provided
  - Previously bypassed cache when fields parameter was present (line 42: `|| fields` condition)
  - Previously didn't cache responses when fields parameter was provided (line 60: `&& fields.nil?` condition)
  - Now correctly uses cache and performs client-side filtering for all calls
  - API endpoint doesn't respect fields parameter anyway, so client-side filtering is always required
  - Added regression test to prevent future cache bypass bugs
- **is_not_empty filter operator** - Fixed FilterBuilder mapping from `{not_null: true}` to `{is_not_null: true}`
  - Resolves "can't prepare TrueClass" error when using `is_not_empty` filter
  - Cache::Query expects `:is_not_null`, not `:not_null` operator
  - Updated tests and documentation
- **Empty field values column mapping** - Fixed column name mapping for empty/null fields in cache query results
  - `map_column_names_to_field_slugs` now correctly handles all fields
  - Prevents missing fields in query results
  - Added comprehensive test coverage
- **Spanish accent handling** - Column names with accents properly transliterated
  - `"Título"` → `"titulo"`, prevents SQL insert failures
  - Added comprehensive Spanish/Latin accent mappings with Unicode normalization
  - Fixes cache insertion failures for tables with Spanish field names
- **Cache column mapping** - Fixed `insert_record` to use stored column names from `field_mapping`
  - Previously regenerated column names, causing SQL insert failures
  - Added `find_matching_value` helper to map extracted values correctly
  - Critical for tables with non-ASCII field names
- **list_tables API response format** - Fixed to handle Array responses from `/applications/` endpoint
  - Normalized `"solution"` field to `"solution_id"` for consistency
  - Resolves issue where list_tables returned 0 results despite 519+ tables existing
- **cached_tables schema** - Updated schema to match SmartSuite API field names
  - Aligned with actual API response structure
  - Improved cache reliability and consistency
- **Broken documentation links** - Fixed 9 broken links across documentation:
  - Fixed incorrect relative paths in `docs/guides/user-guide.md` (lines 594-595) - Changed `../../examples/` to `../examples/`
  - Fixed examples directory reference in `README.md` (line 156) - Changed `examples/` to `docs/examples/`
  - Created missing `docs/getting-started/configuration.md` (referenced in 3 locations)
  - Created missing `docs/reference/filter-operators.md` (referenced in filtering guide)
  - Created missing `docs/contributing/code-style.md`, `testing.md`, and `documentation.md` (referenced in README)

## [1.8.0] - 2025-11-16

### Added

- **Comprehensive test coverage for core modules** (v1.8 - Testing):
  - Added 44 tests for Cache Layer (`test/test_cache_layer.rb`)
  - Added 23 tests for Prompt Registry (`test/test_prompt_registry.rb`)
  - Added 32 tests for Response Formatter (`test/test_response_formatter.rb`)
  - Coverage improved from 68.38% to 82.93% (+14.55 percentage points)
  - Total test suite: 404 tests, 1,419 assertions, all passing
  - **Update (v2.0)**: Coverage further improved to **97.47%** (927 tests, 2,799 assertions), exceeding 90% target
- **Comprehensive CI/CD workflows** for quality assurance:
  - Security scanning with Bundler Audit (weekly + on PR)
  - Code quality checks with Reek
  - Documentation quality with Markdown linting and YARD coverage
  - CHANGELOG enforcement on PRs (auto-skips for Dependabot)
  - Test coverage tracking with SimpleCov (baseline: 68.38% → current: 82.93%, goal: 90%)
- **Dependabot configuration** for automated dependency updates (weekly)
- **New development dependencies**:
  - `simplecov` - Code coverage tracking with detailed reports
  - `reek` - Code smell detection
  - `yard` - Documentation coverage checking
- **Test helper** (`test/test_helper.rb`) for centralized test configuration
- **API::Base module** (`lib/smartsuite/api/base.rb`) - Common helper module for all API operations:
  - Pagination constants (DEFAULT_LIMIT, FETCH_ALL_LIMIT, MAX_LIMIT, DEFAULT_OFFSET)
  - Parameter validation helpers (validate_required_parameter!, validate_optional_parameter!)
  - Endpoint building with URL encoding (build_endpoint)
  - Cache coordination helpers (should_bypass_cache?, log_cache_hit, log_cache_miss)
  - Response building and tracking (build_collection_response, track_response_size, extract_items_from_response)
  - Logging helpers (format_timestamp)
- **FilterBuilder module** (`lib/smartsuite/filter_builder.rb`) - Reusable filter conversion logic:
  - Converts SmartSuite API filter format to cache query conditions
  - Supports 20+ comparison operators (is, is_not, contains, is_greater_than, etc.)
  - 30 test cases with comprehensive edge case coverage
- **Manual integration tests** (`test/integration/`) - Real API validation:
  - Comprehensive integration test suite for all major operations
  - Tests workspace, table, record, member, cache, and stats operations
  - Validates API contract assumptions against real SmartSuite API
  - Run manually with test credentials (not in CI)
  - Includes detailed README with setup instructions and troubleshooting
  - 18 test cases covering happy paths and error scenarios

### Changed

- **BREAKING: Standardized response formats** (v1.8 - Developer Experience):
  - **refresh_cache**: Changed from `{"refreshed": "...", "message": "...", "timestamp": "..."}` to `{"status": "success", "operation": "refresh", "message": "...", "timestamp": "...", "resource": "..."}`
  - **warm_cache**: Added `"operation": "warm"` field, changed no-tables response to use `status: "no_action"`
  - **Error responses**: Changed from `{"error": "message"}` to `{"status": "error", "error": "code", "message": "...", "timestamp": "..."}`
  - All operation responses now include: status, operation, message, timestamp
  - All error responses now include: status='error', error code, message, timestamp
  - Benefits: Consistent structure, better error handling, timestamps aid debugging

- **Modular API operation architecture** (v1.8 - Code Quality):
  - All 8 API operation modules refactored to use Base module:
    - `WorkspaceOperations` - 37 lines reduced, 3 validations added, 2 endpoint simplifications
    - `TableOperations` - 18 lines reduced (33% reduction), 4 validations added
    - `RecordOperations` - 6 validations added, 2 endpoint simplifications
    - `MemberOperations` - 12 lines reduced, 2 validations added, 4 response simplifications
    - `FieldOperations` - Standardized validation with type checking
    - `ViewOperations` - Standardized validation and endpoint building
    - `CommentOperations` - Proof-of-concept implementation
  - Benefits:
    - 35-40% code duplication eliminated across modules
    - Type-safe parameter validation with helpful error messages
    - Consistent cache coordination logic
    - URL-safe endpoint building (proper encoding)
    - Standardized response structure and token tracking
    - Comprehensive YARD documentation (@raise, @example tags)
  - All modules now follow consistent patterns for:
    - Parameter validation (22 new validation calls)
    - Query parameter building (eliminates manual URL construction)
    - Cache coordination (standardized bypass logic)
    - Response building and token tracking
- **Breaking API change**:
  - `should_bypass_cache?` signature changed from optional parameter to keyword argument
  - Before: `should_bypass_cache?(bypass = false)`
  - After: `should_bypass_cache?(bypass: false)`
  - Reason: RuboCop Style/OptionalBooleanParameter compliance
  - Impact: Internal helper method only, no user-facing changes

### Documentation

- **Enhanced YARD documentation coverage** (v1.8 - Developer Experience):
  - Added @example tags to all user-facing MCP modules:
    - SmartSuiteClient: Added examples to `cache`, `stats_tracker`, `initialize`, `warm_cache` methods
    - MCP::ToolRegistry: Added example to `tools_list` method
    - MCP::PromptRegistry: Added examples to `prompts_list`, `prompt_get`, `generate_prompt_text` methods
    - MCP::ResourceRegistry: Added example to `resources_list` method
  - All MCP protocol interface methods now have comprehensive documentation
  - Generated HTML documentation available in `doc/` directory
  - 100% YARD documentation coverage maintained across all 124 public methods
  - Reduced missing @example tags from 87 to 79 (focused on user-facing APIs)

### Fixed

- **Array response handling** in WorkspaceOperations:
  - Fixed `extract_items_from_response` fallback for array responses
  - Proper handling: `response.is_a?(Array) ? response : extract_items_from_response(response)`
  - Important: Empty arrays are truthy in Ruby, so `[] || response` returns []
  - Applied fix in 3 locations to handle both array and hash responses
- **RuboCop compliance** (23 auto-corrections + 2 manual fixes):
  - Added empty lines after module inclusion (6 files)
  - Used modifier if/unless for single-line conditionals (4 locations)
  - Aligned multi-line method arguments (4 locations)
  - Removed redundant parentheses (2 locations)
  - Split long lines (analyze_solution_usage message: 153 → 85 chars)
  - Used safe navigation (&.) in with_cache_coordination
- **YARD documentation** fixes in Migrations module:
  - Removed 7 incorrect @param db tags from instance methods
  - Methods use @db instance variable, not a parameter
- **.gitignore** additions:
  - Added `.yardoc` (YARD cache directory)
  - Added `doc` (YARD HTML output directory)

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

[Unreleased]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.9.0...v2.0.0
[1.9.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/releases/tag/v1.0.0
