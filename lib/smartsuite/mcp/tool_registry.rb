# frozen_string_literal: true

module SmartSuite
  module MCP
    # ToolRegistry manages the MCP tool schemas for SmartSuite operations.
    #
    # This module organizes all available tools into categories (workspace, tables, records, fields,
    # members, stats) and provides methods to generate JSON-RPC responses for tool listing.
    #
    # All tool schemas follow the MCP protocol specification with:
    # - name: Unique identifier for the tool
    # - description: Human-readable description
    # - inputSchema: JSON Schema for parameters
    module ToolRegistry
      # ========================================================================
      # COMMON SCHEMA CONSTANTS
      # ========================================================================
      # These constants reduce duplication across 28 tool definitions.
      # Each parameter schema is used in multiple tools.

      # Table identifier parameter (used in 18+ tools)
      SCHEMA_TABLE_ID = {
        'type' => 'string',
        'description' => 'The ID of the table'
      }.freeze

      # Record identifier parameter (used in 8+ tools)
      SCHEMA_RECORD_ID = {
        'type' => 'string',
        'description' => 'The ID of the record'
      }.freeze

      # Solution identifier parameter (used in 6+ tools)
      SCHEMA_SOLUTION_ID = {
        'type' => 'string',
        'description' => 'The ID of the solution'
      }.freeze

      # Array of record data for bulk add (used in bulk_add_records)
      SCHEMA_RECORDS_ARRAY = {
        'type' => 'array',
        'description' => 'Array of record data hashes (field_slug: value pairs)',
        'items' => { 'type' => 'object' }
      }.freeze

      # Array of record updates for bulk update (used in bulk_update_records)
      SCHEMA_RECORDS_UPDATE_ARRAY = {
        'type' => 'array',
        'description' => 'Array of record hashes with \'id\' and fields to update',
        'items' => { 'type' => 'object' }
      }.freeze

      # Array of record IDs for bulk delete (used in bulk_delete_records)
      SCHEMA_RECORD_IDS_ARRAY = {
        'type' => 'array',
        'description' => 'Array of record IDs to delete',
        'items' => { 'type' => 'string' }
      }.freeze

      # File handle parameter (used in get_file_url)
      SCHEMA_FILE_HANDLE = {
        'type' => 'string',
        'description' => 'File handle from a file/image field'
      }.freeze

      # Preview parameter for deleted records (used in list_deleted_records)
      SCHEMA_PREVIEW = {
        'type' => 'boolean',
        'description' => 'Optional: If true, returns limited fields (default: true)'
      }.freeze

      # File field slug parameter (used in attach_file)
      SCHEMA_FILE_FIELD_SLUG = {
        'type' => 'string',
        'description' => 'The slug of the file/image field to attach files to'
      }.freeze

      # Array of file URLs for attach (used in attach_file)
      SCHEMA_FILE_URLS = {
        'type' => 'array',
        'description' => 'Array of publicly accessible URLs to files. SmartSuite will download and attach these files.',
        'items' => { 'type' => 'string' }
      }.freeze

      # ========================================================================
      # TOOL DEFINITIONS
      # ========================================================================

      # Workspace operation tools for solutions
      # Includes: list_solutions, analyze_solution_usage
      WORKSPACE_TOOLS = [
        {
          'name' => 'list_solutions',
          'description' => 'List all solutions in your SmartSuite workspace (solutions contain tables). Supports fuzzy name search with typo tolerance. ⚠️ STRONGLY RECOMMENDED: Use the "name" parameter to filter solutions and significantly reduce token usage.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'include_activity_data' => {
                'type' => 'boolean',
                'description' => 'Optional: Include usage and activity metrics (status, last_access, records_count, etc.) for identifying inactive solutions. Default: false.'
              },
              'fields' => {
                'type' => 'array',
                'items' => { 'type' => 'string' },
                'description' => 'Optional: Array of field names to request from API (e.g., ["id", "name", "permissions", "created_by"]). Available fields: name, slug, logo_color, logo_icon, description, permissions (with owners array), hidden, created, created_by, updated, updated_by, has_demo_data, status, automation_count, records_count, members_count, sharing_hash, sharing_password, sharing_enabled, sharing_allow_copy, applications_count, last_access, id, delete_date, deleted_by, template. When specified, only these fields are returned from API. When omitted, client-side filtering returns only essential fields (id, name, logo_icon, logo_color).'
              },
              'name' => {
                'type' => 'string',
                'description' => '⚠️ STRONGLY RECOMMENDED for token optimization: Filter solutions by name using fuzzy matching with typo tolerance. Returns only matching solutions instead of all solutions, significantly reducing token usage. Handles partial matches, case-insensitive, accent-insensitive, and allows up to 2 character typos. Examples: "desarollo" matches "Desarrollos de software", "gestion" matches "Gestión de Proyectos", "finanzs" matches "Finanzas". Always use this parameter when you know which solution(s) you need.'
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'analyze_solution_usage',
          'description' => 'Analyze solution usage to identify inactive or underutilized solutions. Returns solutions categorized as inactive, potentially unused, or active based on last access date, record count, and automation activity.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'days_inactive' => {
                'type' => 'number',
                'description' => 'Optional: Number of days since last access to consider a solution inactive. Default: 90.'
              },
              'min_records' => {
                'type' => 'number',
                'description' => 'Optional: Minimum number of records for a solution to not be considered empty. Default: 10.'
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'list_solutions_by_owner',
          'description' => 'List solutions owned by a specific user. Fetches all solutions, filters client-side by owner ID from permissions.owners array, and returns only matching solutions with essential fields.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'owner_id' => {
                'type' => 'string',
                'description' => 'User ID of the solution owner (e.g., from list_members result)'
              },
              'include_activity_data' => {
                'type' => 'boolean',
                'description' => 'Optional: Include usage and activity metrics (status, last_access, records_count, etc.). Default: false.'
              }
            },
            'required' => ['owner_id']
          }
        },
        {
          'name' => 'get_solution_most_recent_record_update',
          'description' => 'Get the most recent record update timestamp across all tables in a solution. Useful for determining if a solution has recent data activity even without UI access.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'solution_id' => {
                'type' => 'string',
                'description' => 'Solution ID to check for most recent record update'
              }
            },
            'required' => ['solution_id']
          }
        }
      ].freeze

      # Table operation tools for table management
      # Includes: list_tables, get_table, create_table
      TABLE_TOOLS = [
        {
          'name' => 'list_tables',
          'description' => 'List all tables (apps) in your SmartSuite workspace. Optionally filter by solution_id and/or specify which fields to return.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'solution_id' => {
                'type' => 'string',
                'description' => 'Optional: Filter tables by solution ID. Use list_solutions first to get solution IDs.'
              },
              'fields' => {
                'type' => 'array',
                'items' => { 'type' => 'string' },
                'description' => 'Optional: Array of field slugs to include in response (e.g., ["name", "id", "structure"]). When specified, only these fields are returned. When omitted, returns only essential fields (id, name, solution_id) for minimal token usage.'
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'get_table',
          'description' => 'Get a specific table by ID including its structure (fields, their slugs, types, etc). Use this BEFORE querying records to understand what fields are available for filtering and selection.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table to retrieve'
              }
            },
            'required' => ['table_id']
          }
        },
        {
          'name' => 'create_table',
          'description' => 'Create a new table (application) in a SmartSuite solution.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'solution_id' => {
                'type' => 'string',
                'description' => 'The ID of the solution where the table will be created'
              },
              'name' => {
                'type' => 'string',
                'description' => 'Name of the new table'
              },
              'description' => {
                'type' => 'string',
                'description' => 'Optional: Description for the table'
              },
              'structure' => {
                'type' => 'array',
                'description' => 'Optional: Array of field definitions for the table. If not provided, an empty array will be used.',
                'items' => {
                  'type' => 'object'
                }
              }
            },
            'required' => %w[solution_id name]
          }
        }
      ].freeze

      # Record operation tools for CRUD operations on table records
      # Includes: list_records, get_record, create_record, update_record, delete_record,
      #           bulk_add_records, bulk_update_records, bulk_delete_records,
      #           get_file_url, list_deleted_records, restore_deleted_record
      RECORD_TOOLS = [
        {
          'name' => 'list_records',
          'description' => 'List records from a SmartSuite table with filtering, sorting, and field selection. ⚠️ CRITICAL FOR EFFICIENCY: (1) ALWAYS use filter parameter to request only relevant records - do NOT fetch all records and filter manually! (2) ALWAYS specify MINIMAL fields - only request fields you actually need. Field values are NOT truncated, so requesting unnecessary fields wastes tokens. (3) Use small limit values (5-10) initially to preview data, then increase if needed. Returns plain text format showing "X of Y filtered records (Z total)" to help you understand the data. REQUIRED: Must specify fields parameter.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table to query'
              },
              'limit' => {
                'type' => 'number',
                'description' => 'Maximum number of records to return (default: 10). ⚠️ START SMALL: Use 5-10 initially to preview data efficiently, only increase if more records are needed after reviewing results. Applied after filtering.'
              },
              'offset' => {
                'type' => 'number',
                'description' => 'Number of records to skip for pagination (default: 0).'
              },
              'filter' => {
                'type' => 'object',
                'description' => '⚠️ STRONGLY RECOMMENDED: Filter criteria to request only relevant records - ALWAYS use this instead of fetching all records! STRUCTURE: {"operator": "and|or", "fields": [{"field": "field_slug", "comparison": "operator", "value": "value"}]}. EXAMPLES: 1) Status filter: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}. 2) Multiple conditions: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}, {"field": "priority", "comparison": "is_greater_than", "value": 3}]}. 3) Date range: {"operator": "and", "fields": [{"field": "due_date", "comparison": "is_after", "value": {"date_mode": "exact_date", "date_mode_value": "2025-01-01"}}]}. OPERATORS: is, is_not, contains, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than, is_empty, is_not_empty, has_any_of, has_all_of, is_exactly, is_before, is_after. NOTE: Date fields require value as object with date_mode and date_mode_value.'
              },
              'sort' => {
                'type' => 'array',
                'description' => 'Sort criteria applied to results. Array of field-direction pairs. Example: [{"field": "created_on", "direction": "desc"}].',
                'items' => {
                  'type' => 'object',
                  'properties' => {
                    'field' => {
                      'type' => 'string',
                      'description' => 'Field slug to sort by'
                    },
                    'direction' => {
                      'type' => 'string',
                      'description' => 'Sort direction: "asc" or "desc"',
                      'enum' => %w[asc desc]
                    }
                  }
                }
              },
              'fields' => {
                'type' => 'array',
                'description' => 'REQUIRED: Array of field slugs to return (e.g., ["status", "priority"]). ⚠️ CRITICAL: Specify ONLY the minimum fields needed - values are NOT truncated, so requesting unnecessary fields (especially long text, descriptions, notes) wastes many tokens. Start with 2-3 key fields to understand the data, then request additional fields only if actually needed. Example: ["status", "priority"] is much more efficient than ["title", "status", "priority", "description", "notes", "comments"].',
                'items' => {
                  'type' => 'string'
                }
              },
              'hydrated' => {
                'type' => 'boolean',
                'description' => 'Optional: If true (default), fetches human-readable values for linked records, users, and other reference fields. If false, returns raw IDs. Default: true.'
              }
            },
            'required' => %w[table_id fields]
          }
        },
        {
          'name' => 'get_record',
          'description' => 'Get a specific record by ID from a SmartSuite table',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table'
              },
              'record_id' => {
                'type' => 'string',
                'description' => 'The ID of the record to retrieve'
              }
            },
            'required' => %w[table_id record_id]
          }
        },
        {
          'name' => 'create_record',
          'description' => 'Create a new record in a SmartSuite table.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table'
              },
              'data' => {
                'type' => 'object',
                'description' => 'The record data as key-value pairs (field_slug: value)'
              }
            },
            'required' => %w[table_id data]
          }
        },
        {
          'name' => 'update_record',
          'description' => 'Update an existing record in a SmartSuite table.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table'
              },
              'record_id' => {
                'type' => 'string',
                'description' => 'The ID of the record to update'
              },
              'data' => {
                'type' => 'object',
                'description' => 'The record data to update as key-value pairs (field_slug: value)'
              }
            },
            'required' => %w[table_id record_id data]
          }
        },
        {
          'name' => 'delete_record',
          'description' => 'Delete a record from a SmartSuite table.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table'
              },
              'record_id' => {
                'type' => 'string',
                'description' => 'The ID of the record to delete'
              }
            },
            'required' => %w[table_id record_id]
          }
        },
        {
          'name' => 'bulk_add_records',
          'description' => 'Create multiple records in a single request (bulk operation). More efficient than multiple create_record calls when adding many records.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => SCHEMA_TABLE_ID,
              'records' => SCHEMA_RECORDS_ARRAY
            },
            'required' => %w[table_id records]
          }
        },
        {
          'name' => 'bulk_update_records',
          'description' => 'Update multiple records in a single request (bulk operation). More efficient than multiple update_record calls. Each record hash must include \'id\' field along with fields to update.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => SCHEMA_TABLE_ID,
              'records' => SCHEMA_RECORDS_UPDATE_ARRAY
            },
            'required' => %w[table_id records]
          }
        },
        {
          'name' => 'bulk_delete_records',
          'description' => 'Delete multiple records in a single request (bulk operation). More efficient than multiple delete_record calls. Performs soft delete - records can be restored using restore_deleted_record.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => SCHEMA_TABLE_ID,
              'record_ids' => SCHEMA_RECORD_IDS_ARRAY
            },
            'required' => %w[table_id record_ids]
          }
        },
        {
          'name' => 'get_file_url',
          'description' => 'Get a public URL for a file attached to a record. The file handle can be found in file/image field values. Returns a public URL with a 20-year lifetime.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'file_handle' => SCHEMA_FILE_HANDLE
            },
            'required' => ['file_handle']
          }
        },
        {
          'name' => 'list_deleted_records',
          'description' => 'List deleted records from a solution. Returns records that have been soft-deleted and can be restored.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'solution_id' => SCHEMA_SOLUTION_ID,
              'preview' => SCHEMA_PREVIEW
            },
            'required' => ['solution_id']
          }
        },
        {
          'name' => 'restore_deleted_record',
          'description' => 'Restore a deleted record. Restores a soft-deleted record back to the table. The restored record will have "(Restored)" appended to its title.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => SCHEMA_TABLE_ID,
              'record_id' => SCHEMA_RECORD_ID
            },
            'required' => %w[table_id record_id]
          }
        },
        {
          'name' => 'attach_file',
          'description' => 'Attach files to a record by providing URLs. SmartSuite downloads files from the provided URLs and attaches them to the specified file/image field. The URLs must be publicly accessible.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => SCHEMA_TABLE_ID,
              'record_id' => SCHEMA_RECORD_ID,
              'file_field_slug' => SCHEMA_FILE_FIELD_SLUG,
              'file_urls' => SCHEMA_FILE_URLS
            },
            'required' => %w[table_id record_id file_field_slug file_urls]
          }
        }
      ].freeze

      # Field operation tools for managing table schema (add, update, delete fields)
      # Includes: add_field, bulk_add_fields, update_field, delete_field
      FIELD_TOOLS = [
        {
          'name' => 'add_field',
          'description' => 'Add a new field to a SmartSuite table. Returns the created field object.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table to add the field to'
              },
              'field_data' => {
                'type' => 'object',
                'description' => 'Field configuration object with slug, label, field_type, and params. Example: {"slug": "abc123defg", "label": "My Field", "field_type": "textfield", "params": {"help_text": "Enter text"}, "is_new": true}'
              },
              'field_position' => {
                'type' => 'object',
                'description' => 'Optional: Position metadata. Example: {"prev_sibling_slug": "field_slug"} to place after another field'
              },
              'auto_fill_structure_layout' => {
                'type' => 'boolean',
                'description' => 'Optional: Enable automatic layout structure updates (default: true)'
              }
            },
            'required' => %w[table_id field_data]
          }
        },
        {
          'name' => 'bulk_add_fields',
          'description' => 'Add multiple fields to a SmartSuite table in one request. Note: Certain field types are not supported in bulk operations (e.g., Formula, Count, TimeTracking).',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table to add fields to'
              },
              'fields' => {
                'type' => 'array',
                'description' => 'Array of field configuration objects. Each should have slug, label, field_type, icon, params, and is_new.',
                'items' => {
                  'type' => 'object'
                }
              },
              'set_as_visible_fields_in_reports' => {
                'type' => 'array',
                'description' => 'Optional: Array of view (report) IDs where the added fields should be visible',
                'items' => {
                  'type' => 'string'
                }
              }
            },
            'required' => %w[table_id fields]
          }
        },
        {
          'name' => 'update_field',
          'description' => 'Update an existing field in a SmartSuite table. Returns the updated field object.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table containing the field'
              },
              'slug' => {
                'type' => 'string',
                'description' => 'The slug of the field to update'
              },
              'field_data' => {
                'type' => 'object',
                'description' => 'Updated field configuration object with label, field_type, and params. Example: {"label": "Updated Label", "field_type": "textfield", "params": {"help_text": "New help text"}}'
              }
            },
            'required' => %w[table_id slug field_data]
          }
        },
        {
          'name' => 'delete_field',
          'description' => 'Delete a field from a SmartSuite table. Returns the deleted field object.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table containing the field'
              },
              'slug' => {
                'type' => 'string',
                'description' => 'The slug of the field to delete'
              }
            },
            'required' => %w[table_id slug]
          }
        }
      ].freeze

      # Member operation tools for workspace user management
      # Includes: list_members (with optional solution filtering), list_teams, get_team
      MEMBER_TOOLS = [
        {
          'name' => 'list_members',
          'description' => 'List all members (users) in your SmartSuite workspace. Use this to get user IDs for assigning people to records. Optionally filter by solution_id to only show members who have access to that solution (saves tokens).',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'limit' => {
                'type' => 'number',
                'description' => 'Maximum number of members to return (default: 100). Ignored when solution_id is provided.'
              },
              'offset' => {
                'type' => 'number',
                'description' => 'Number of members to skip (for pagination). Ignored when solution_id is provided.'
              },
              'solution_id' => {
                'type' => 'string',
                'description' => 'Optional: Filter members by solution ID. Returns only members who have access to this solution. This saves tokens by filtering server-side.'
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'list_teams',
          'description' => 'List all teams in your SmartSuite workspace. Teams are groups of users that can be assigned permissions to solutions and tables.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {},
            'required' => []
          }
        },
        {
          'name' => 'get_team',
          'description' => 'Get a specific team by ID. Returns team details including members.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'team_id' => {
                'type' => 'string',
                'description' => 'The ID of the team to retrieve'
              }
            },
            'required' => ['team_id']
          }
        },
        {
          'name' => 'search_member',
          'description' => 'Search for members by name or email. Performs case-insensitive search across email, first name, last name, and full name fields. Returns only matching members to minimize token usage.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'query' => {
                'type' => 'string',
                'description' => 'Search query for name or email (case-insensitive)'
              }
            },
            'required' => ['query']
          }
        }
      ].freeze

      # Statistics tools for API usage monitoring
      # Includes: get_api_stats, reset_api_stats, get_cache_status, refresh_cache, warm_cache
      STATS_TOOLS = [
        {
          'name' => 'get_api_stats',
          'description' => 'Get API call statistics tracked by user, solution, table, and HTTP method. Includes cache performance metrics (hit/miss counts, hit rates, efficiency ratios, token savings). Supports time range filtering.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'time_range' => {
                'type' => 'string',
                'description' => 'Time range for statistics: "session" (current session only), "7d" (last 7 days), "all" (all time). Default: "all"',
                'enum' => %w[session 7d all]
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'reset_api_stats',
          'description' => 'Reset all API call statistics',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {},
            'required' => []
          }
        },
        {
          'name' => 'get_cache_status',
          'description' => 'Get cache status for solutions, tables, and records. Shows cached_at, expires_at, time_remaining, record_count, and validity. Helps understand cache state and plan refreshes.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'Optional: Specific table ID to show status for. If not provided, shows status for all cached tables.'
              }
            },
            'required' => []
          }
        },
        {
          'name' => 'refresh_cache',
          'description' => 'Manually refresh (invalidate) cache for specific resources. Invalidates cache without refetching - data will be refreshed on next access. Useful for forcing fresh data when you know it has changed. IMPORTANT: Choose the right resource level based on what you want to refresh.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'resource' => {
                'type' => 'string',
                'description' => 'Resource type to refresh with cascading invalidation: (1) "solutions" = invalidates ALL solutions + ALL tables + ALL records (use only when refreshing entire workspace), (2) "tables" with solution_id = invalidates tables + records for ONE specific solution (use this to refresh a single solution), (3) "tables" without solution_id = invalidates ALL tables + ALL records, (4) "records" with table_id = invalidates records for ONE specific table. Examples: To refresh "ProductEK" solution use resource="tables" with solution_id="sol_123", NOT resource="solutions".',
                'enum' => %w[solutions tables records]
              },
              'table_id' => {
                'type' => 'string',
                'description' => 'Table ID (required when resource is "records"). Use this to refresh cache for a specific table only. Example: resource="records", table_id="tbl_456"'
              },
              'solution_id' => {
                'type' => 'string',
                'description' => 'Solution ID (required when refreshing a specific solution). Use with resource="tables" to refresh one solution. Example: To refresh "ProductEK" solution, use resource="tables" with solution_id="sol_123". Omit to refresh all tables.'
              }
            },
            'required' => ['resource']
          }
        },
        {
          'name' => 'warm_cache',
          'description' => 'Proactively warm (populate) cache for specified tables or auto-select top accessed tables. Fetches and caches all records to improve subsequent query performance. Skips tables that already have valid cache.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'tables' => {
                'description' => 'Table IDs to warm. Can be: array of table IDs, single table ID string, "auto" (top N accessed), or omit for auto mode. Examples: ["tbl_123", "tbl_456"], "tbl_123", "auto"',
                'oneOf' => [
                  {
                    'type' => 'array',
                    'items' => { 'type' => 'string' },
                    'description' => 'Array of table IDs to warm'
                  },
                  {
                    'type' => 'string',
                    'description' => 'Single table ID or "auto" for automatic selection'
                  }
                ]
              },
              'count' => {
                'type' => 'number',
                'description' => 'Number of tables to warm in auto mode (default: 5). Only used when tables is "auto" or omitted.',
                'default' => 5
              }
            },
            'required' => []
          }
        }
      ].freeze

      # Comment operation tools for managing record comments
      # Includes: list_comments, add_comment
      COMMENT_TOOLS = [
        {
          'name' => 'list_comments',
          'description' => 'List all comments for a specific record. Returns an array of comment objects with message content, author, timestamps, and assignment information.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'record_id' => {
                'type' => 'string',
                'description' => 'The ID of the record whose comments to retrieve'
              }
            },
            'required' => ['record_id']
          }
        },
        {
          'name' => 'add_comment',
          'description' => 'Add a comment to a record. Returns the created comment object. Comments support plain text which is automatically formatted to rich text.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table/application containing the record'
              },
              'record_id' => {
                'type' => 'string',
                'description' => 'The ID of the record to add the comment to'
              },
              'message' => {
                'type' => 'string',
                'description' => 'The comment text (plain text will be automatically converted to rich text format)'
              },
              'assigned_to' => {
                'type' => 'string',
                'description' => 'Optional: User ID to assign the comment to. Use list_members to get user IDs.'
              }
            },
            'required' => %w[table_id record_id message]
          }
        }
      ].freeze

      # View operation tools for view/report management
      # Includes: get_view_records, create_view
      VIEW_TOOLS = [
        {
          'name' => 'get_view_records',
          'description' => 'Get records for a specified view (report) with the view\'s filters, sorting, and field visibility applied. Views define which records are shown based on filters and how they are displayed.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table containing the view'
              },
              'view_id' => {
                'type' => 'string',
                'description' => 'The ID of the view (report) to get records from'
              },
              'with_empty_values' => {
                'type' => 'boolean',
                'description' => 'Optional: Whether to include empty field values in the response. Default: false.'
              }
            },
            'required' => %w[table_id view_id]
          }
        },
        {
          'name' => 'create_view',
          'description' => 'Create a new view (report) in a SmartSuite table. Views allow you to filter, sort, group, and display records in different formats (grid, calendar, map, kanban, etc.).',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'application' => {
                'type' => 'string',
                'description' => 'The ID of the table where the view will be created'
              },
              'solution' => {
                'type' => 'string',
                'description' => 'The ID of the solution containing the table'
              },
              'label' => {
                'type' => 'string',
                'description' => 'Display name of the view'
              },
              'view_mode' => {
                'type' => 'string',
                'description' => 'View type: grid, map, calendar, kanban, gallery, timeline, or gantt'
              },
              'description' => {
                'type' => 'string',
                'description' => 'Optional: Description of the view'
              },
              'autosave' => {
                'type' => 'boolean',
                'description' => 'Optional: Enable autosave (default: true)'
              },
              'is_locked' => {
                'type' => 'boolean',
                'description' => 'Optional: Lock the view (default: false)'
              },
              'is_private' => {
                'type' => 'boolean',
                'description' => 'Optional: Make view private (default: false)'
              },
              'is_password_protected' => {
                'type' => 'boolean',
                'description' => 'Optional: Password protect view (default: false)'
              },
              'order' => {
                'type' => 'number',
                'description' => 'Optional: Display position in view list'
              },
              'state' => {
                'type' => 'object',
                'description' => 'Optional: View state configuration (filter, fields, sort, group settings)'
              },
              'map_state' => {
                'type' => 'object',
                'description' => 'Optional: Map configuration for map views'
              },
              'sharing' => {
                'type' => 'object',
                'description' => 'Optional: Sharing settings for the view'
              }
            },
            'required' => %w[application solution label view_mode]
          }
        }
      ].freeze

      # All tools combined into a single array for MCP protocol responses
      # Total: 28 tools across 8 categories (4 workspace, 3 table, 11 record, 4 field, 4 member, 2 comment, 2 view, 5 stats)
      ALL_TOOLS = (WORKSPACE_TOOLS + TABLE_TOOLS + RECORD_TOOLS + FIELD_TOOLS + MEMBER_TOOLS + COMMENT_TOOLS + VIEW_TOOLS + STATS_TOOLS).freeze

      # Generates a JSON-RPC 2.0 response for the tools/list MCP method.
      #
      # @param request [Hash] The MCP request containing the request ID
      # @return [Hash] JSON-RPC 2.0 response with all available tools
      # @example Generate tools list response
      #   request = {"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      #   response = SmartSuite::MCP::ToolRegistry.tools_list(request)
      #   # => {"jsonrpc" => "2.0", "id" => 1, "result" => {"tools" => [...]}}
      def self.tools_list(request)
        {
          'jsonrpc' => '2.0',
          'id' => request['id'],
          'result' => {
            'tools' => ALL_TOOLS
          }
        }
      end
    end
  end
end
