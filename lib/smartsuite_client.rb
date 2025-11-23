# frozen_string_literal: true

require 'json'
require_relative 'api_stats_tracker'
require_relative 'smartsuite/api/http_client'
require_relative 'smartsuite/api/workspace_operations'
require_relative 'smartsuite/api/table_operations'
require_relative 'smartsuite/api/record_operations'
require_relative 'smartsuite/api/field_operations'
require_relative 'smartsuite/api/member_operations'
require_relative 'smartsuite/api/comment_operations'
require_relative 'smartsuite/api/view_operations'
require_relative 'smartsuite/formatters/response_formatter'
require_relative 'smartsuite/response_formats'
require_relative 'smartsuite/paths'
require_relative 'smartsuite/cache/layer'

# SmartSuiteClient is the main client for interacting with the SmartSuite API.
#
# This class provides a unified interface for all SmartSuite operations by including
# specialized operation modules. It handles authentication, caching, API statistics,
# and response formatting.
#
# Key features:
# - Workspace operations (solutions, usage analysis)
# - Table operations (list, get, create)
# - Record operations (CRUD)
# - Field operations (add, update, delete fields)
# - Member operations (list users, teams, search)
# - Comment operations (list, add comments)
# - View operations (get records, create views)
# - SQLite-based caching with configurable TTL
# - API statistics tracking with session support
# - Token usage optimization via response filtering
#
# @example Basic usage
#   client = SmartSuiteClient.new(api_key, account_id)
#   solutions = client.list_solutions
#   tables = client.list_tables
#   records = client.list_records('tbl_123', 10, 0, fields: ['status', 'priority'])
#
# @example With caching disabled
#   client = SmartSuiteClient.new(api_key, account_id, cache_enabled: false)
#
# @example With custom cache path and session ID
#   client = SmartSuiteClient.new(api_key, account_id,
#                                  cache_path: '/tmp/cache.db',
#                                  session_id: 'my_session')
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
  include SmartSuite::ResponseFormats

  # @!attribute [r] cache
  #   @return [SmartSuite::Cache::Layer, nil] cache layer instance, or nil if caching disabled
  #   @example Access cache status
  #     client.cache.cache_valid?('tbl_123')
  #
  # @!attribute [r] stats_tracker
  #   @return [ApiStatsTracker, nil] API statistics tracker instance
  #   @example Get API stats
  #     stats = client.stats_tracker.get_api_stats
  attr_reader :cache, :stats_tracker

  # Initialize a new SmartSuiteClient instance.
  #
  # Creates a client with authentication credentials and optional caching.
  # When caching is enabled, creates a SQLite database for persistent storage
  # and shares it with the API statistics tracker.
  #
  # @param api_key [String] SmartSuite API key for authentication
  # @param account_id [String] SmartSuite account ID
  # @param stats_tracker [ApiStatsTracker, nil] Optional external stats tracker (used when cache disabled)
  # @param cache_enabled [Boolean] Enable SQLite-based caching (default: true)
  # @param cache_path [String, nil] Custom path for cache database (default: ~/.smartsuite_mcp_cache.db)
  # @param session_id [String, nil] Custom session ID for tracking (default: auto-generated)
  # @return [SmartSuiteClient] configured client instance
  # @example Basic initialization
  #   client = SmartSuiteClient.new(ENV['SMARTSUITE_API_KEY'], ENV['SMARTSUITE_ACCOUNT_ID'])
  #
  # @example With caching disabled
  #   client = SmartSuiteClient.new(api_key, account_id, cache_enabled: false)
  #
  # @example With custom configuration
  #   client = SmartSuiteClient.new(api_key, account_id,
  #                                  cache_path: '/tmp/cache.db',
  #                                  session_id: 'my_session')
  def initialize(api_key, account_id, stats_tracker: nil, cache_enabled: true, cache_path: nil, session_id: nil)
    @api_key = api_key
    @account_id = account_id

    # Generate unique session ID if not provided
    @session_id = session_id || "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{rand(36**6).to_s(36)}"

    # Create a separate, clean log file for metrics (must be before any log_metric calls)
    # Uses SmartSuite::Paths for consistent path handling (test mode vs production)
    @metrics_log = File.open(SmartSuite::Paths.metrics_log_path, 'a')
    @metrics_log.sync = true # Auto-flush

    # Token usage tracking
    @total_tokens_used = 0
    @context_limit = 200_000 # Claude's context window

    # Initialize cache layer
    if cache_enabled
      @cache = SmartSuite::Cache::Layer.new(db_path: cache_path)
      log_metric("✓ Cache layer initialized: #{@cache.db_path}")
      log_metric("✓ Session ID: #{@session_id}")

      # Initialize stats tracker to use same database as cache with session tracking
      @stats_tracker = ApiStatsTracker.new(api_key, db: @cache.db, session_id: @session_id)
      log_metric('✓ Stats tracker sharing cache database')
    else
      @cache = nil
      @stats_tracker = stats_tracker # Use provided tracker or nil
      log_metric('⚠ Cache layer disabled')
    end
  end

  # Check if caching is enabled for this client.
  #
  # @return [Boolean] true if cache layer is initialized, false otherwise
  # @example
  #   client.cache_enabled? #=> true
  def cache_enabled?
    !@cache.nil?
  end
end
