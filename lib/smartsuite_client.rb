require 'json'
require_relative 'smartsuite/api/http_client'
require_relative 'smartsuite/api/workspace_operations'
require_relative 'smartsuite/api/table_operations'
require_relative 'smartsuite/api/record_operations'
require_relative 'smartsuite/api/field_operations'
require_relative 'smartsuite/api/member_operations'
require_relative 'smartsuite/api/comment_operations'
require_relative 'smartsuite/api/view_operations'
require_relative 'smartsuite/formatters/response_formatter'
require_relative 'smartsuite/cache_layer'

class SmartSuiteClient
  include SmartSuite::API::HttpClient
  include SmartSuite::API::WorkspaceOperations
  include SmartSuite::API::TableOperations
  include SmartSuite::API::RecordOperations
  include SmartSuite::API::FieldOperations
  include SmartSuite::API::MemberOperations
  include SmartSuite::API::CommentOperations
  include SmartSuite::API::ViewOperations
  include SmartSuite::Formatters::ResponseFormatter

  attr_reader :cache

  def initialize(api_key, account_id, stats_tracker: nil, cache_enabled: true, cache_path: nil)
    @api_key = api_key
    @account_id = account_id
    @stats_tracker = stats_tracker

    # Create a separate, clean log file for metrics (must be before any log_metric calls)
    @metrics_log = File.open(File.join(Dir.home, '.smartsuite_mcp_metrics.log'), 'a')
    @metrics_log.sync = true  # Auto-flush

    # Token usage tracking
    @total_tokens_used = 0
    @context_limit = 200000  # Claude's context window

    # Initialize cache layer
    if cache_enabled
      @cache = SmartSuite::CacheLayer.new(db_path: cache_path)
      log_metric("✓ Cache layer initialized: #{@cache.db_path}")
    else
      @cache = nil
      log_metric("⚠ Cache layer disabled")
    end
  end

  def cache_enabled?
    !@cache.nil?
  end
end
