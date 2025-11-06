require 'json'
require_relative 'smartsuite/api/http_client'
require_relative 'smartsuite/api/workspace_operations'
require_relative 'smartsuite/api/table_operations'
require_relative 'smartsuite/api/record_operations'
require_relative 'smartsuite/api/field_operations'
require_relative 'smartsuite/api/member_operations'
require_relative 'smartsuite/api/view_operations'
require_relative 'smartsuite/formatters/response_formatter'

class SmartSuiteClient
  include SmartSuite::API::HttpClient
  include SmartSuite::API::WorkspaceOperations
  include SmartSuite::API::TableOperations
  include SmartSuite::API::RecordOperations
  include SmartSuite::API::FieldOperations
  include SmartSuite::API::MemberOperations
  include SmartSuite::API::ViewOperations
  include SmartSuite::Formatters::ResponseFormatter

  def initialize(api_key, account_id, stats_tracker: nil)
    @api_key = api_key
    @account_id = account_id
    @stats_tracker = stats_tracker

    # Create a separate, clean log file for metrics
    @metrics_log = File.open(File.join(Dir.home, '.smartsuite_mcp_metrics.log'), 'a')
    @metrics_log.sync = true  # Auto-flush

    # Token usage tracking
    @total_tokens_used = 0
    @context_limit = 200000  # Claude's context window
  end
end
