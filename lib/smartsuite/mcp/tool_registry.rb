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
      # Workspace operation tools for solutions
      # Includes: list_solutions, analyze_solution_usage
      WORKSPACE_TOOLS = [
        {
          'name' => 'list_solutions',
          'description' => 'List all solutions in your SmartSuite workspace (solutions contain tables)',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'include_activity_data' => {
                'type' => 'boolean',
                'description' => 'Optional: Include usage and activity metrics (status, last_access, records_count, etc.) for identifying inactive solutions. Default: false.'
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
                'items' => {'type' => 'string'},
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
            'required' => ['solution_id', 'name']
          }
        }
      ].freeze

      # Record operation tools for CRUD operations on table records
      # Includes: list_records, get_record, create_record, update_record, delete_record
      RECORD_TOOLS = [
        {
          'name' => 'list_records',
          'description' => 'List records from a SmartSuite table. DEFAULT: Returns only id + title for minimal context usage. Use fields parameter for specific data or summary_only for statistics.',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {
              'table_id' => {
                'type' => 'string',
                'description' => 'The ID of the table to query'
              },
              'limit' => {
                'type' => 'number',
                'description' => 'Maximum number of records to return (default: 5 for minimal context usage)'
              },
              'offset' => {
                'type' => 'number',
                'description' => 'Number of records to skip (for pagination)'
              },
              'filter' => {
                'type' => 'object',
                'description' => 'Filter criteria. STRUCTURE: {"operator": "and|or", "fields": [{"field": "field_slug", "comparison": "operator", "value": "value"}]}. EXAMPLES: 1) Single filter: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}]}. 2) Multiple filters: {"operator": "and", "fields": [{"field": "status", "comparison": "is", "value": "active"}, {"field": "priority", "comparison": "is_greater_than", "value": 3}]}. 3) Date filter (IMPORTANT - use date value object): {"operator": "and", "fields": [{"field": "due_date", "comparison": "is_after", "value": {"date_mode": "exact_date", "date_mode_value": "2025-01-01"}}]}. OPERATORS: is, is_not, contains, is_greater_than, is_less_than, is_empty, is_not_empty, is_before, is_after. NOTE: Date fields require value as object with date_mode and date_mode_value.'
              },
              'sort' => {
                'type' => 'array',
                'description' => 'Sort criteria as array of field-direction pairs. Example: [{"field": "created_on", "direction": "desc"}]',
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
                      'enum' => ['asc', 'desc']
                    }
                  }
                }
              },
              'fields' => {
                'type' => 'array',
                'description' => 'Optional: Specific field slugs to return. Default returns only id + title. Specify fields to get additional data.',
                'items' => {
                  'type' => 'string'
                }
              },
              'summary_only' => {
                'type' => 'boolean',
                'description' => 'If true, returns statistics/summary instead of actual records. Minimal context usage for overview purposes.'
              },
              'full_content' => {
                'type' => 'boolean',
                'description' => 'If true, returns full field content without truncation. Default (false): strings truncated to 500 chars. Use when you need complete field values (like full descriptions) to avoid multiple get_record calls.'
              }
            },
            'required' => ['table_id']
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
            'required' => ['table_id', 'record_id']
          }
        },
        {
          'name' => 'create_record',
          'description' => 'Create a new record in a SmartSuite table',
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
            'required' => ['table_id', 'data']
          }
        },
        {
          'name' => 'update_record',
          'description' => 'Update an existing record in a SmartSuite table',
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
            'required' => ['table_id', 'record_id', 'data']
          }
        },
        {
          'name' => 'delete_record',
          'description' => 'Delete a record from a SmartSuite table',
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
            'required' => ['table_id', 'record_id']
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
            'required' => ['table_id', 'field_data']
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
            'required' => ['table_id', 'fields']
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
            'required' => ['table_id', 'slug', 'field_data']
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
            'required' => ['table_id', 'slug']
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
        }
      ].freeze

      # Statistics tools for API usage monitoring
      # Includes: get_api_stats, reset_api_stats
      STATS_TOOLS = [
        {
          'name' => 'get_api_stats',
          'description' => 'Get API call statistics tracked by user, solution, table, and HTTP method',
          'inputSchema' => {
            'type' => 'object',
            'properties' => {},
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
            'required' => ['table_id', 'record_id', 'message']
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
            'required' => ['table_id', 'view_id']
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
            'required' => ['application', 'solution', 'label', 'view_mode']
          }
        }
      ].freeze

      # All tools combined into a single array for MCP protocol responses
      # Total: 22 tools across 8 categories
      ALL_TOOLS = (WORKSPACE_TOOLS + TABLE_TOOLS + RECORD_TOOLS + FIELD_TOOLS + MEMBER_TOOLS + COMMENT_TOOLS + VIEW_TOOLS + STATS_TOOLS).freeze

      # Generates a JSON-RPC 2.0 response for the tools/list MCP method.
      #
      # @param request [Hash] The MCP request containing the request ID
      # @return [Hash] JSON-RPC 2.0 response with all available tools
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
