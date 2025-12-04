# frozen_string_literal: true

class ApiCall < ApplicationRecord
  belongs_to :user

  validates :tool_name, presence: true

  scope :today, -> { where('created_at > ?', Time.current.beginning_of_day) }
  scope :this_month, -> { where('created_at > ?', Time.current.beginning_of_month) }
  scope :cache_hits, -> { where(cache_hit: true) }
  scope :cache_misses, -> { where(cache_hit: false) }
end
