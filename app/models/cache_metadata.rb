# frozen_string_literal: true

class CacheMetadata < ApplicationRecord
  self.primary_key = :table_id

  validates :table_id, presence: true, uniqueness: true
  validates :pg_table_name, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :valid, -> { where("expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def valid?
    !expired?
  end

  def time_remaining
    return 0 if expired?

    (expires_at - Time.current).to_i
  end

  def refresh_expiry!
    update!(
      cached_at: Time.current,
      expires_at: Time.current + ttl_seconds.seconds
    )
  end
end
