# frozen_string_literal: true

# Load Rails test environment for PostgreSQL integration tests
ENV["RAILS_ENV"] ||= "test"

require_relative "../../../config/environment"
require "minitest/autorun"

# Test helper for PostgreSQL integration tests
#
# These tests run against a real PostgreSQL database to verify that
# JSONB queries work correctly with actual data, not just SQL generation.
#
# Requirements:
# - Rails test environment configured
# - Database migrations run (rails db:test:prepare)
module PostgresIntegrationHelper
  # Sample table structure mimicking SmartSuite fields
  TEST_TABLE_STRUCTURE = {
    "id" => "test_table_001",
    "name" => "Integration Test Table",
    "solution" => "test_solution_001",
    "structure" => [
      { "slug" => "title", "label" => "Title", "field_type" => "recordtitlefield" },
      { "slug" => "status", "label" => "Status", "field_type" => "statusfield" },
      { "slug" => "priority", "label" => "Priority", "field_type" => "singleselectfield" },
      { "slug" => "description", "label" => "Description", "field_type" => "textfield" },
      { "slug" => "amount", "label" => "Amount", "field_type" => "numberfield" },
      { "slug" => "due_date", "label" => "Due Date", "field_type" => "duedatefield" },
      { "slug" => "created_date", "label" => "Created Date", "field_type" => "datefield" },
      { "slug" => "assigned_to", "label" => "Assigned To", "field_type" => "userfield" },
      { "slug" => "tags", "label" => "Tags", "field_type" => "multipleselectfield" },
      { "slug" => "linked_records", "label" => "Linked Records", "field_type" => "linkedrecordfield" },
      { "slug" => "is_active", "label" => "Is Active", "field_type" => "yesnofield" }
    ]
  }.freeze

  TEST_TABLE_ID = "test_table_001"

  # Sample records with various data patterns to test all filter scenarios
  def self.sample_records
    [
      # Record 1: Complete data - status as object, due_date as Date Range structure
      {
        "id" => "rec_001",
        "title" => "Complete Task",
        "status" => { "value" => "in_progress", "updated_on" => "2025-01-01T00:00:00Z" },
        "priority" => "high",
        "description" => "This is a complete task with all fields filled",
        "amount" => 1500.50,
        "due_date" => {
          "from_date" => { "date" => "2025-06-01T00:00:00Z", "include_time" => false },
          "to_date" => { "date" => "2025-06-15T00:00:00Z", "include_time" => false }
        },
        "created_date" => "2025-01-15",
        "assigned_to" => [ "user_001", "user_002" ],
        "tags" => [ "urgent", "bug", "frontend" ],
        "linked_records" => [ "rec_other_001", "rec_other_002" ],
        "is_active" => true
      },
      # Record 2: Status as simple string (legacy format), empty arrays
      {
        "id" => "rec_002",
        "title" => "Empty Arrays Task",
        "status" => { "value" => "complete", "updated_on" => "2025-02-01T00:00:00Z" },
        "priority" => "low",
        "description" => "Task with empty arrays",
        "amount" => 250,
        "due_date" => {
          "from_date" => nil,
          "to_date" => { "date" => "2025-07-01T00:00:00Z", "include_time" => false }
        },
        "created_date" => "2025-02-01",
        "assigned_to" => [], # Empty array
        "tags" => [], # Empty array
        "linked_records" => [], # Empty array
        "is_active" => false
      },
      # Record 3: Null values
      {
        "id" => "rec_003",
        "title" => "Null Values Task",
        "status" => { "value" => "backlog", "updated_on" => "2025-03-01T00:00:00Z" },
        "priority" => nil,
        "description" => nil,
        "amount" => nil,
        "due_date" => {
          "from_date" => nil,
          "to_date" => nil # Null to_date
        },
        "created_date" => nil,
        "assigned_to" => nil,
        "tags" => nil,
        "linked_records" => nil,
        "is_active" => nil
      },
      # Record 4: Simple date format (not Date Range)
      {
        "id" => "rec_004",
        "title" => "Simple Date Task",
        "status" => { "value" => "in_progress", "updated_on" => "2025-04-01T00:00:00Z" },
        "priority" => "medium",
        "description" => "Contains special characters: café, naïve, résumé",
        "amount" => 999.99,
        "due_date" => {
          "from_date" => { "date" => "2025-05-01T00:00:00Z", "include_time" => false },
          "to_date" => { "date" => "2025-05-15T00:00:00Z", "include_time" => false }
        },
        "created_date" => "2025-04-01",
        "assigned_to" => [ "user_001" ],
        "tags" => [ "documentation" ],
        "linked_records" => [ "rec_other_003" ],
        "is_active" => true
      },
      # Record 5: Due date as string (alternative format)
      {
        "id" => "rec_005",
        "title" => "String Due Date Task",
        "status" => { "value" => "complete", "updated_on" => "2025-05-01T00:00:00Z" },
        "priority" => "high",
        "description" => "Task with string due date format",
        "amount" => 0,
        "due_date" => {
          "from_date" => "2025-08-01",
          "to_date" => "2025-08-31" # String format, not nested object
        },
        "created_date" => "2025-05-01",
        "assigned_to" => [ "user_003" ],
        "tags" => [ "feature", "backend" ],
        "linked_records" => [],
        "is_active" => true
      },
      # Record 6: Empty object for due_date (edge case)
      {
        "id" => "rec_006",
        "title" => "Empty Due Date Task",
        "status" => { "value" => "backlog", "updated_on" => "2025-06-01T00:00:00Z" },
        "priority" => "low",
        "description" => "",  # Empty string
        "amount" => 50,
        "due_date" => {}, # Empty object
        "created_date" => "2025-06-01",
        "assigned_to" => {},  # Empty object (unusual but possible)
        "tags" => [ "misc" ],
        "linked_records" => {},  # Empty object
        "is_active" => false
      },
      # Record 7: Large amount for numeric testing
      {
        "id" => "rec_007",
        "title" => "High Value Task",
        "status" => { "value" => "in_progress", "updated_on" => "2025-07-01T00:00:00Z" },
        "priority" => "high",
        "description" => "Enterprise client project with high budget",
        "amount" => 50000,
        "due_date" => {
          "from_date" => { "date" => "2025-09-01T00:00:00Z", "include_time" => false },
          "to_date" => { "date" => "2025-12-31T00:00:00Z", "include_time" => false }
        },
        "created_date" => "2025-07-01",
        "assigned_to" => [ "user_001", "user_002", "user_003" ],
        "tags" => [ "enterprise", "priority", "q4" ],
        "linked_records" => [ "rec_other_001", "rec_other_002", "rec_other_003" ],
        "is_active" => true
      }
    ]
  end

  # Setup test database with sample data
  def setup_test_data
    @cache = Cache::PostgresLayer.new
    @table_id = TEST_TABLE_ID

    # Clear any existing test data
    clear_test_data

    # Insert test records
    now = Time.current
    expires_at = now + 1.hour

    PostgresIntegrationHelper.sample_records.each do |record|
      execute_raw_sql(
        "INSERT INTO cache_records (table_id, record_id, data, cached_at, expires_at) VALUES ($1, $2, $3, $4, $5)",
        [ @table_id, record["id"], record.to_json, now, expires_at ]
      )
    end
  end

  def clear_test_data
    execute_raw_sql("DELETE FROM cache_records WHERE table_id = $1", [ @table_id ])
  end

  def execute_raw_sql(sql, params = [])
    conn = ActiveRecord::Base.connection.raw_connection
    conn.exec_params(sql, params)
  end

  # Helper to run a filter and get record IDs
  def filter_record_ids(filter)
    records = @cache.get_cached_records(@table_id, filter: filter)
    records&.map { |r| r["id"] }&.sort || []
  end

  # Helper to build filter
  def build_filter(field:, comparison:, value: nil)
    {
      "operator" => "and",
      "fields" => [
        { "field" => field, "comparison" => comparison, "value" => value }
      ]
    }
  end
end
