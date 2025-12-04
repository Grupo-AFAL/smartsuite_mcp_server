# frozen_string_literal: true

require "json"
require_relative "api_stats_tracker"
require_relative "smartsuite/logger"
require_relative "smartsuite/date_formatter"
require_relative "smartsuite/api/http_client"
require_relative "smartsuite/api/workspace_operations"
require_relative "smartsuite/api/table_operations"
require_relative "smartsuite/api/record_operations"
require_relative "smartsuite/api/field_operations"
require_relative "smartsuite/api/member_operations"
require_relative "smartsuite/api/comment_operations"
require_relative "smartsuite/api/view_operations"
require_relative "smartsuite/formatters/response_formatter"
require_relative "smartsuite/response_formats"
require_relative "smartsuite/paths"
require_relative "smartsuite/cache/layer"

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
  # @param cache [Object, nil] Custom cache adapter instance (overrides cache_enabled/cache_path)
  # @param session_id [String, nil] Custom session ID for tracking (default: auto-generated)
  # @return [SmartSuiteClient] configured client instance
  # @example Basic initialization
  #   client = SmartSuiteClient.new(ENV['SMARTSUITE_API_KEY'], ENV['SMARTSUITE_ACCOUNT_ID'])
  #
  # @example With caching disabled
  #   client = SmartSuiteClient.new(api_key, account_id, cache_enabled: false)
  #
  # @example With custom cache adapter (e.g., PostgreSQL)
  #   client = SmartSuiteClient.new(api_key, account_id, cache: Cache::PostgresLayer.new)
  #
  # @example With custom configuration
  #   client = SmartSuiteClient.new(api_key, account_id,
  #                                  cache_path: '/tmp/cache.db',
  #                                  session_id: 'my_session')
  def initialize(api_key, account_id, stats_tracker: nil, cache_enabled: true, cache_path: nil, cache: nil, session_id: nil)
    @api_key = api_key
    @account_id = account_id

    # Generate unique session ID if not provided
    @session_id = session_id || "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{rand(36**6).to_s(36)}"

    # Token usage tracking
    @total_tokens_used = 0
    @context_limit = 200_000 # Claude's context window

    # Initialize cache layer
    if cache
      # Use injected cache adapter (e.g., PostgreSQL for hosted mode)
      @cache = cache
      @stats_tracker = stats_tracker
      SmartSuite::Logger.metric("✓ Cache layer initialized (injected adapter: #{cache.class.name})")
      SmartSuite::Logger.metric("✓ Session ID: #{@session_id}")
    elsif cache_enabled
      @cache = SmartSuite::Cache::Layer.new(db_path: cache_path)
      SmartSuite::Logger.metric("✓ Cache layer initialized: #{@cache.db_path}")
      SmartSuite::Logger.metric("✓ Session ID: #{@session_id}")

      # Initialize stats tracker to use same database as cache with session tracking
      @stats_tracker = ApiStatsTracker.new(api_key, db: @cache.db, session_id: @session_id)
      SmartSuite::Logger.metric("✓ Stats tracker sharing cache database")
    else
      @cache = nil
      @stats_tracker = stats_tracker # Use provided tracker or nil
      SmartSuite::Logger.metric("⚠ Cache layer disabled")
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

  # Configure timezone from the current user's SmartSuite profile.
  #
  # Fetches the first member (typically the API key owner) and configures
  # DateFormatter with their timezone setting. This ensures dates display
  # consistently with what the user sees in the SmartSuite UI.
  #
  # @return [String, nil] The configured timezone, or nil if not found
  # @example Configure with environment variable
  #   # Set SMARTSUITE_USER_EMAIL=user@example.com before starting
  #   client.configure_user_timezone
  #   #=> "America/Mexico_City"
  #
  # @example Fallback behavior (no email configured)
  #   # Uses first member with timezone set
  #   client.configure_user_timezone
  #   #=> "America/Chicago"
  def configure_user_timezone
    # Check if user email is configured via environment variable
    user_email = ENV.fetch("SMARTSUITE_USER_EMAIL", nil)

    if user_email
      # Search for the specific user by email
      result = search_member(user_email, format: :json)
      if result.is_a?(Hash) && result["members"].is_a?(Array)
        member = result["members"].find { |m| m["email"]&.downcase == user_email.downcase }
        if member && member["timezone"]
          SmartSuite::DateFormatter.timezone = member["timezone"]
          SmartSuite::Logger.info("Configured timezone from user #{user_email}: #{member['timezone']}")
          return member["timezone"]
        end
      end
      SmartSuite::Logger.warn("User #{user_email} not found or has no timezone set")
    end

    # Fallback: fetch members and use first one with timezone
    members = list_members(limit: 10, format: :json)

    return nil unless members.is_a?(Hash) && members["members"].is_a?(Array)

    # Find a member with timezone set (first one found)
    member_with_tz = members["members"].find { |m| m["timezone"] }

    if member_with_tz && member_with_tz["timezone"]
      timezone = member_with_tz["timezone"]
      SmartSuite::DateFormatter.timezone = timezone
      SmartSuite::Logger.info("Configured timezone from user profile: #{timezone}")
      timezone
    else
      SmartSuite::Logger.info("No timezone found in user profile, using system default")
      nil
    end
  rescue StandardError => e
    SmartSuite::Logger.warn("Failed to configure timezone from user profile: #{e.message}")
    nil
  end
end
