# frozen_string_literal: true

class APIKey < ApplicationRecord
  belongs_to :user

  before_create :generate_token

  validates :token, uniqueness: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Authenticate and update last_used_at
  def self.authenticate(token)
    return nil if token.blank?

    key = active.find_by(token: token)
    key&.touch(:last_used_at)
    key
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  private

  def generate_token
    self.token ||= "ss_#{SecureRandom.hex(24)}"
  end
end
