# frozen_string_literal: true

# Tracks API calls for analytics and monitoring
# Only tracks tool calls (not initialize, list tools, etc.)
# Skips tracking for LocalUser (non-persisted users in local mode)
class APICallTracker
  attr_reader :user, :request_body, :duration_ms

  def initialize(user:, request_body:, duration_ms:)
    @user = user
    @request_body = request_body
    @duration_ms = duration_ms
  end

  def track
    return unless trackable?

    APICall.create(
      user: user,
      tool_name: tool_name,
      cache_hit: cache_hit?,
      solution_id: resolved_solution_id,
      table_id: table_id,
      duration_ms: duration_ms
    )
  rescue StandardError => e
    Rails.logger.warn("Failed to track API call: #{e.message}")
  end

  private

  def trackable?
    tools_call? && user.present? && !local_user?
  end

  def tools_call?
    request_body["method"] == "tools/call"
  end

  def local_user?
    user.is_a?(LocalUser)
  end

  def tool_name
    request_body.dig("params", "name")
  end

  def table_id
    request_body.dig("params", "arguments", "table_id")
  end

  def solution_id
    request_body.dig("params", "arguments", "solution_id")
  end

  def resolved_solution_id
    return solution_id if solution_id.present?
    return nil unless table_id

    lookup_solution_id_for_table
  end

  def cache_hit?
    Cache::PostgresLayer.cache_hit_for_request?
  end

  def lookup_solution_id_for_table
    result = ActiveRecord::Base.connection.select_one(
      ActiveRecord::Base.sanitize_sql_array([
        "SELECT solution_id FROM cache_tables WHERE table_id = ?",
        table_id
      ])
    )
    result&.fetch("solution_id", nil)
  rescue StandardError => e
    Rails.logger.debug("Failed to lookup solution_id for table #{table_id}: #{e.message}")
    nil
  end
end
