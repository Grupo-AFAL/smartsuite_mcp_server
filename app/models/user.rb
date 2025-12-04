# frozen_string_literal: true

class User < ApplicationRecord
  has_many :api_keys, dependent: :destroy
  has_many :api_calls, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :smartsuite_api_key, presence: true
  validates :smartsuite_account_id, presence: true

  # Usage statistics
  def api_calls_today
    api_calls.where('created_at > ?', Time.current.beginning_of_day).count
  end

  def api_calls_this_month
    api_calls.where('created_at > ?', Time.current.beginning_of_month).count
  end

  def api_calls_by_tool(since: 30.days.ago)
    api_calls.where('created_at > ?', since).group(:tool_name).count
  end

  def cache_hit_rate(since: 30.days.ago)
    calls = api_calls.where('created_at > ?', since)
    total = calls.count
    return 0.0 if total.zero?

    hits = calls.where(cache_hit: true).count
    (hits.to_f / total * 100).round(2)
  end
end
