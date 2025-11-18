# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Added

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
  - Cache-first strategy: fuzzy matching happens at SQLite layer when using cache
  - Fallback client-side filtering for non-cached responses
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
  - Improved `bypass_cache` documentation
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

### Changed

- **README.md** - Completely restructured Quick Start section:
  - **One-liner installation** now featured as primary method (easiest!)
  - Manual clone + script moved to "Alternative" section
  - Removed verbose prerequisites (bootstrap scripts handle git checks)
  - Simplified and streamlined documentation
  - Focus on "paste one command, enter credentials, done"
- **ROADMAP.md** - Updated v2.0 goals to focus on "Token optimization and ease of installation"

### Fixed

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
  - Remaining gap to 90% target: 7.07%
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

[Unreleased]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/Grupo-AFAL/smartsuite_mcp_server/releases/tag/v1.0.0
