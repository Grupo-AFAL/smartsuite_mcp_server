# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/smartsuite/mcp/prompt_registry'

class TestPromptRegistry < Minitest::Test
  # Test prompts_list method
  def test_prompts_list_returns_all_prompts
    request = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'prompts/list' }

    response = SmartSuite::MCP::PromptRegistry.prompts_list(request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 1, response['id']
    assert response['result'].key?('prompts')
    assert response['result']['prompts'].is_a?(Array)
    assert response['result']['prompts'].size >= 10, 'Should have at least 10 prompts'
  end

  def test_prompts_list_includes_filter_active_records
    request = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'prompts/list' }

    response = SmartSuite::MCP::PromptRegistry.prompts_list(request)
    prompts = response['result']['prompts']

    prompt = prompts.find { |p| p['name'] == 'filter_active_records' }
    assert prompt, 'Should include filter_active_records prompt'
    assert_equal 'Example: Filter records where status is "active"', prompt['description']
    assert prompt['arguments'].is_a?(Array)
  end

  # Test prompt_get method
  def test_prompt_get_returns_prompt_text
    request = {
      'jsonrpc' => '2.0',
      'id' => 2,
      'method' => 'prompts/get',
      'params' => {
        'name' => 'filter_active_records',
        'arguments' => {
          'table_id' => 'tbl_123',
          'status_field' => 'status',
          'fields' => 'id,title,status'
        }
      }
    }

    response = SmartSuite::MCP::PromptRegistry.prompt_get(request)

    assert_equal '2.0', response['jsonrpc']
    assert_equal 2, response['id']
    assert response['result'].key?('messages')
    assert_equal 1, response['result']['messages'].size

    message = response['result']['messages'][0]
    assert_equal 'user', message['role']
    assert_equal 'text', message['content']['type']
    assert message['content']['text'].is_a?(String)
    assert_includes message['content']['text'], 'tbl_123'
  end

  # Test filter_active_records prompt generation
  def test_generate_filter_active_records_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'status_field' => 'status',
      'fields' => 'id,name,status'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_active_records', arguments)

    assert_includes text, 'list_records'
    assert_includes text, 'tbl_123'
    assert_includes text, 'status'
    assert_includes text, 'active'
    assert_includes text, '["id", "name", "status"]'
    assert_includes text, 'NOTE: When cache is enabled'
  end

  def test_generate_filter_active_records_with_defaults
    arguments = {
      'table_id' => 'tbl_456',
      'fields' => 'id,status'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_active_records', arguments)

    assert_includes text, 'tbl_456'
    assert_includes text, '"field": "status"', "Should default to 'status' field"
  end

  # Test filter_by_date_range prompt generation
  def test_generate_filter_by_date_range_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'date_field' => 'due_date',
      'start_date' => '2025-01-01',
      'end_date' => '2025-01-31',
      'fields' => 'id,due_date,title'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_date_range', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'due_date'
    assert_includes text, '2025-01-01'
    assert_includes text, '2025-01-31'
    assert_includes text, 'is_after'
    assert_includes text, 'is_before'
  end

  # Test list_tables_by_solution prompt generation
  def test_generate_list_tables_by_solution_prompt
    arguments = {
      'solution_id' => 'sol_789'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('list_tables_by_solution', arguments)

    assert_includes text, 'list_tables'
    assert_includes text, 'sol_789'
  end

  # Test filter_records_contains_text prompt generation
  def test_generate_filter_contains_text_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'field_slug' => 'description',
      'search_text' => 'urgent',
      'fields' => 'id,description'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_records_contains_text', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'description'
    assert_includes text, 'urgent'
    assert_includes text, 'contains'
  end

  # Test filter_by_linked_record prompt generation
  def test_generate_filter_by_linked_record_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'linked_field_slug' => 'project',
      'record_ids' => 'rec_1,rec_2,rec_3',
      'fields' => 'id,project'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_linked_record', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'project'
    assert_includes text, 'has_any_of'
    assert_includes text, '["rec_1", "rec_2", "rec_3"]'
    assert_includes text, 'Linked record fields require'
  end

  # Test filter_by_numeric_range prompt generation
  def test_generate_filter_by_numeric_range_with_min_and_max
    arguments = {
      'table_id' => 'tbl_123',
      'numeric_field_slug' => 'amount',
      'min_value' => '1000',
      'max_value' => '5000',
      'fields' => 'id,amount'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_numeric_range', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'amount'
    assert_includes text, 'is_equal_or_greater_than'
    assert_includes text, '1000'
    assert_includes text, 'is_equal_or_less_than'
    assert_includes text, '5000'
  end

  def test_generate_filter_by_numeric_range_with_min_only
    arguments = {
      'table_id' => 'tbl_123',
      'numeric_field_slug' => 'amount',
      'min_value' => '1000',
      'fields' => 'id,amount'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_numeric_range', arguments)

    assert_includes text, 'is_equal_or_greater_than'
    assert_includes text, '1000'
    # Should not have a max_value condition in the filter (note: the help text may still mention the operator)
    filter_section = text.split('filter: {')[1].split('}')[0]
    refute_includes filter_section, 'is_equal_or_less_than', 'Filter should not include max value condition'
  end

  # Test filter_by_multiple_select prompt generation
  def test_generate_filter_by_multiple_select_any
    arguments = {
      'table_id' => 'tbl_123',
      'multiselect_field_slug' => 'tags',
      'values' => 'urgent,bug,feature',
      'match_type' => 'any',
      'fields' => 'id,tags'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_multiple_select', arguments)

    assert_includes text, 'tags'
    assert_includes text, 'has_any_of'
    assert_includes text, '["urgent", "bug", "feature"]'
  end

  def test_generate_filter_by_multiple_select_all
    arguments = {
      'table_id' => 'tbl_123',
      'multiselect_field_slug' => 'tags',
      'values' => 'urgent,bug',
      'match_type' => 'all',
      'fields' => 'id,tags'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_multiple_select', arguments)

    assert_includes text, 'has_all_of'
  end

  def test_generate_filter_by_multiple_select_exact
    arguments = {
      'table_id' => 'tbl_123',
      'multiselect_field_slug' => 'tags',
      'values' => 'urgent',
      'match_type' => 'exact',
      'fields' => 'id,tags'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_multiple_select', arguments)

    assert_includes text, 'is_exactly'
  end

  # Test filter_by_assigned_user prompt generation
  def test_generate_filter_by_assigned_user_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'user_field_slug' => 'assigned_to',
      'user_ids' => 'user_1,user_2',
      'fields' => 'id,assigned_to'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_assigned_user', arguments)

    assert_includes text, 'assigned_to'
    assert_includes text, 'has_any_of'
    assert_includes text, '["user_1", "user_2"]'
    assert_includes text, 'list_members'
  end

  # Test filter_by_empty_fields prompt generation
  def test_generate_filter_by_empty_fields_empty
    arguments = {
      'table_id' => 'tbl_123',
      'field_slug' => 'description',
      'check_type' => 'empty',
      'fields' => 'id,description'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_empty_fields', arguments)

    assert_includes text, 'description'
    assert_includes text, 'is_empty'
    assert_includes text, 'null'
  end

  def test_generate_filter_by_empty_fields_not_empty
    arguments = {
      'table_id' => 'tbl_123',
      'field_slug' => 'description',
      'check_type' => 'not_empty',
      'fields' => 'id,description'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_empty_fields', arguments)

    assert_includes text, 'is_not_empty'
  end

  # Test filter_by_recent_updates prompt generation
  def test_generate_filter_by_recent_updates_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'days_ago' => '7',
      'fields' => 'id,title'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_by_recent_updates', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 's5b629ed5f', 'Should use system Last Updated field'
    assert_includes text, 'is_on_or_after'
    assert_includes text, 'exact_date'
  end

  # Test filter_complex_and_or prompt generation
  def test_generate_filter_complex_and_or_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'status_field_slug' => 'status',
      'priority_field_slug' => 'priority',
      'status_values' => 'active,pending',
      'fields' => 'id,status,priority'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_complex_and_or', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'status'
    assert_includes text, 'priority'
    assert_includes text, 'is_any_of'
    assert_includes text, '["active", "pending"]'
  end

  # Test filter_overdue_tasks prompt generation
  def test_generate_filter_overdue_tasks_prompt
    arguments = {
      'table_id' => 'tbl_123',
      'due_date_field_slug' => 'due_date',
      'fields' => 'id,title,due_date'
    }

    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('filter_overdue_tasks', arguments)

    assert_includes text, 'tbl_123'
    assert_includes text, 'due_date'
    assert_includes text, 'is_overdue'
    assert_includes text, 'Due Date fields'
  end

  # Test unknown prompt
  def test_generate_unknown_prompt
    text = SmartSuite::MCP::PromptRegistry.generate_prompt_text('unknown_prompt', {})

    assert_includes text, 'Unknown prompt'
    assert_includes text, 'unknown_prompt'
  end

  # Test all prompts are defined
  def test_all_prompts_have_required_fields
    SmartSuite::MCP::PromptRegistry::PROMPTS.each do |prompt|
      assert prompt.key?('name'), "Prompt should have 'name' field: #{prompt.inspect}"
      assert prompt.key?('description'), "Prompt should have 'description' field: #{prompt.inspect}"
      assert prompt.key?('arguments'), "Prompt should have 'arguments' field: #{prompt.inspect}"

      # Check arguments structure
      prompt['arguments'].each do |arg|
        assert arg.key?('name'), "Argument should have 'name' field: #{arg.inspect}"
        assert arg.key?('description'), "Argument should have 'description' field: #{arg.inspect}"
        assert arg.key?('required'), "Argument should have 'required' field: #{arg.inspect}"
      end
    end
  end

  # Test prompt names are unique
  def test_prompt_names_are_unique
    names = SmartSuite::MCP::PromptRegistry::PROMPTS.map { |p| p['name'] }
    unique_names = names.uniq

    assert_equal unique_names.size, names.size, 'All prompt names should be unique'
  end
end
