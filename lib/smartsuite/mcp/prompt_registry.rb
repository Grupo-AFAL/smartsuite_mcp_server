# frozen_string_literal: true

module SmartSuite
  module MCP
    # PromptRegistry manages MCP prompt templates for common SmartSuite operations.
    #
    # Prompts are pre-configured examples that demonstrate how to use tools with
    # common filter patterns. Each prompt includes:
    # - name: Unique identifier
    # - description: What the prompt demonstrates
    # - arguments: Required and optional parameters
    module PromptRegistry
      # All available prompt templates for common operations
      # Includes examples for filtering, date ranges, and text search
      PROMPTS = [
        {
          'name' => 'filter_active_records',
          'description' => 'Example: Filter records where status is "active"',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'status_field',
              'description' => 'The field slug for status (default: "status")',
              'required' => false
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_date_range',
          'description' => 'Example: Filter records within a date range',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'date_field',
              'description' => 'The field slug for the date field',
              'required' => true
            },
            {
              'name' => 'start_date',
              'description' => 'Start date (YYYY-MM-DD format)',
              'required' => true
            },
            {
              'name' => 'end_date',
              'description' => 'End date (YYYY-MM-DD format)',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'list_tables_by_solution',
          'description' => 'Example: List all tables in a specific solution',
          'arguments' => [
            {
              'name' => 'solution_id',
              'description' => 'The solution ID to filter by',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_records_contains_text',
          'description' => 'Example: Filter records where a field contains specific text',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'field_slug',
              'description' => 'The field slug to search in',
              'required' => true
            },
            {
              'name' => 'search_text',
              'description' => 'The text to search for',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_linked_record',
          'description' => 'Example: Filter records by linked record field (uses has_any_of with record IDs)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'linked_field_slug',
              'description' => 'The linked record field slug',
              'required' => true
            },
            {
              'name' => 'record_ids',
              'description' => 'Comma-separated list of linked record IDs',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_numeric_range',
          'description' => 'Example: Filter records by numeric field (amount, rating, etc.)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'numeric_field_slug',
              'description' => 'The numeric field slug',
              'required' => true
            },
            {
              'name' => 'min_value',
              'description' => 'Minimum value (inclusive)',
              'required' => false
            },
            {
              'name' => 'max_value',
              'description' => 'Maximum value (inclusive)',
              'required' => false
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_multiple_select',
          'description' => 'Example: Filter records by multiple select or tag field',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'multiselect_field_slug',
              'description' => 'The multiple select or tag field slug',
              'required' => true
            },
            {
              'name' => 'values',
              'description' => 'Comma-separated list of values to match',
              'required' => true
            },
            {
              'name' => 'match_type',
              'description' => 'Match type: any (has_any_of), all (has_all_of), or exact (is_exactly)',
              'required' => false
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_assigned_user',
          'description' => 'Example: Filter records by assigned user field',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'user_field_slug',
              'description' => 'The user/assigned to field slug',
              'required' => true
            },
            {
              'name' => 'user_ids',
              'description' => 'Comma-separated list of user IDs',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_empty_fields',
          'description' => 'Example: Filter records where a field is empty or not empty (v1.6+)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'field_slug',
              'description' => 'The field slug to check',
              'required' => true
            },
            {
              'name' => 'check_empty',
              'description' => 'true to find empty fields, false to find non-empty fields',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_by_recent_updates',
          'description' => 'Example: Filter records updated within last N days (v1.6+)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'days',
              'description' => 'Number of days to look back (e.g., 7 for last week)',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_complex_and_or',
          'description' => 'Example: Complex filter with AND/OR conditions (v1.6+)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'operator',
              'description' => 'Logical operator: "and" or "or"',
              'required' => true
            },
            {
              'name' => 'conditions',
              'description' => 'JSON string of filter conditions array',
              'required' => true
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        },
        {
          'name' => 'filter_overdue_tasks',
          'description' => 'Example: Filter overdue tasks using due date field (v1.6+)',
          'arguments' => [
            {
              'name' => 'table_id',
              'description' => 'The table ID to query',
              'required' => true
            },
            {
              'name' => 'due_date_field',
              'description' => 'The due date field slug (default: "due_date")',
              'required' => false
            },
            {
              'name' => 'fields',
              'description' => 'Comma-separated list of field slugs to return',
              'required' => true
            }
          ]
        }
      ].freeze

      # Generates a JSON-RPC 2.0 response for the prompts/list MCP method.
      #
      # @param request [Hash] The MCP request containing the request ID
      # @return [Hash] JSON-RPC 2.0 response with all available prompts
      def self.prompts_list(request)
        {
          'jsonrpc' => '2.0',
          'id' => request['id'],
          'result' => {
            'prompts' => PROMPTS
          }
        }
      end

      # Generates a JSON-RPC 2.0 response for the prompts/get MCP method.
      #
      # Retrieves a specific prompt template and fills it with provided arguments.
      #
      # @param request [Hash] The MCP request containing prompt name and arguments
      # @return [Hash] JSON-RPC 2.0 response with the generated prompt text
      def self.prompt_get(request)
        prompt_name = request.dig('params', 'name')
        arguments = request.dig('params', 'arguments') || {}

        prompt_text = generate_prompt_text(prompt_name, arguments)

        {
          'jsonrpc' => '2.0',
          'id' => request['id'],
          'result' => {
            'messages' => [
              {
                'role' => 'user',
                'content' => {
                  'type' => 'text',
                  'text' => prompt_text
                }
              }
            ]
          }
        }
      end

      # Generates the actual prompt text based on the prompt name and arguments.
      #
      # @param prompt_name [String] Name of the prompt template to use
      # @param arguments [Hash] Arguments to fill into the template
      # @return [String] Generated prompt text with instructions
      def self.generate_prompt_text(prompt_name, arguments)
        case prompt_name
        when 'filter_active_records'
          status_field = arguments['status_field'] || 'status'
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{status_field}\",\n" \
            "      \"comparison\": \"is\",\n" \
            "      \"value\": \"active\"\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_date_range'
          date_field = arguments['date_field']
          start_date = arguments['start_date']
          end_date = arguments['end_date']
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{date_field}\",\n" \
            "      \"comparison\": \"is_after\",\n" \
            "      \"value\": {\n" \
            "        \"date_mode\": \"exact_date\",\n" \
            "        \"date_mode_value\": \"#{start_date}\"\n" \
            "      }\n" \
            "    },\n" \
            "    {\n" \
            "      \"field\": \"#{date_field}\",\n" \
            "      \"comparison\": \"is_before\",\n" \
            "      \"value\": {\n" \
            "        \"date_mode\": \"exact_date\",\n" \
            "        \"date_mode_value\": \"#{end_date}\"\n" \
            "      }\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'list_tables_by_solution'
          "Use the list_tables tool with this parameter:\n\n" \
            "solution_id: #{arguments['solution_id']}\n\n" \
            'This will return only tables from the specified solution.'

        when 'filter_records_contains_text'
          field_slug = arguments['field_slug']
          search_text = arguments['search_text']
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{field_slug}\",\n" \
            "      \"comparison\": \"contains\",\n" \
            "      \"value\": \"#{search_text}\"\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_linked_record'
          linked_field = arguments['linked_field_slug']
          record_ids = arguments['record_ids']&.split(',')&.map(&:strip) || []
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{linked_field}\",\n" \
            "      \"comparison\": \"has_any_of\",\n" \
            "      \"value\": #{record_ids.inspect}\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Linked record fields require 'has_any_of' comparison (not 'is') with an array of record IDs.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_numeric_range'
          numeric_field = arguments['numeric_field_slug']
          min_value = arguments['min_value']
          max_value = arguments['max_value']
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          filter_conditions = []
          if min_value
            filter_conditions << "    {\n" \
                                 "      \"field\": \"#{numeric_field}\",\n" \
                                 "      \"comparison\": \"is_equal_or_greater_than\",\n" \
                                 "      \"value\": #{min_value}\n" \
                                 '    }'
          end
          if max_value
            filter_conditions << "    {\n" \
                                 "      \"field\": \"#{numeric_field}\",\n" \
                                 "      \"comparison\": \"is_equal_or_less_than\",\n" \
                                 "      \"value\": #{max_value}\n" \
                                 '    }'
          end

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" +
            filter_conditions.join(",\n") + "\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Numeric fields support: is_equal_to, is_not_equal_to, is_greater_than, is_less_than, is_equal_or_greater_than, is_equal_or_less_than\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_multiple_select'
          multiselect_field = arguments['multiselect_field_slug']
          values = arguments['values']&.split(',')&.map(&:strip) || []
          match_type = arguments['match_type'] || 'any'
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          comparison = case match_type
                       when 'any' then 'has_any_of'
                       when 'all' then 'has_all_of'
                       when 'exact' then 'is_exactly'
                       else 'has_any_of'
                       end

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{multiselect_field}\",\n" \
            "      \"comparison\": \"#{comparison}\",\n" \
            "      \"value\": #{values.inspect}\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Multiple select fields support: has_any_of (matches any), has_all_of (matches all), is_exactly (exact match), has_none_of\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_assigned_user'
          user_field = arguments['user_field_slug']
          user_ids = arguments['user_ids']&.split(',')&.map(&:strip) || []
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{user_field}\",\n" \
            "      \"comparison\": \"has_any_of\",\n" \
            "      \"value\": #{user_ids.inspect}\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: User fields require 'has_any_of' comparison with an array of user IDs. Use list_members to get user IDs.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_empty_fields'
          field_slug = arguments['field_slug']
          check_type = arguments['check_type'] || 'empty'
          fields = arguments['fields']&.split(',')&.map(&:strip) || []
          comparison = check_type == 'empty' ? 'is_empty' : 'is_not_empty'

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{field_slug}\",\n" \
            "      \"comparison\": \"#{comparison}\",\n" \
            "      \"value\": null\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Empty field checks use 'is_empty' or 'is_not_empty' operators with null value. Works for all field types.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_by_recent_updates'
          days_ago = arguments['days_ago'] || '7'
          fields = arguments['fields']&.split(',')&.map(&:strip) || []
          cutoff_date = (Time.now.utc - (days_ago.to_i * 24 * 60 * 60)).strftime('%Y-%m-%d')

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"s5b629ed5f\",\n" \
            "      \"comparison\": \"is_on_or_after\",\n" \
            "      \"value\": {\n" \
            "        \"date_mode\": \"exact_date\",\n" \
            "        \"date_mode_value\": \"#{cutoff_date}\"\n" \
            "      }\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Uses the system 'Last Updated' field (slug: s5b629ed5f) with date comparison. For custom date fields, use their specific slugs.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_complex_and_or'
          status_field = arguments['status_field_slug']
          priority_field = arguments['priority_field_slug']
          status_values = arguments['status_values']&.split(',')&.map(&:strip) || []
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{status_field}\",\n" \
            "      \"comparison\": \"is_any_of\",\n" \
            "      \"value\": #{status_values.inspect}\n" \
            "    },\n" \
            "    {\n" \
            "      \"field\": \"#{priority_field}\",\n" \
            "      \"comparison\": \"is\",\n" \
            "      \"value\": \"High\"\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: Complex filters can combine multiple conditions with 'and' or 'or' operators. Each field condition supports different comparison operators based on field type.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        when 'filter_overdue_tasks'
          due_date_field = arguments['due_date_field_slug']
          fields = arguments['fields']&.split(',')&.map(&:strip) || []

          "Use the list_records tool with these parameters:\n\n" \
            "table_id: #{arguments['table_id']}\n" \
            "fields: #{fields.inspect}\n" \
            "filter: {\n" \
            "  \"operator\": \"and\",\n" \
            "  \"fields\": [\n" \
            "    {\n" \
            "      \"field\": \"#{due_date_field}\",\n" \
            "      \"comparison\": \"is_overdue\",\n" \
            "      \"value\": null\n" \
            "    }\n" \
            "  ]\n" \
            "}\n\n" \
            "Note: The 'is_overdue' comparison is specifically for Due Date fields. For regular date fields, use 'is_before' with today's date.\n\n" \
            'NOTE: When cache is enabled (default), the filter parameter above is IGNORED and all filtering is done locally on cached data. The filter is only used if cache is disabled or bypass_cache=true is set.'

        else
          "Unknown prompt: #{prompt_name}"
        end
      end
    end
  end
end
