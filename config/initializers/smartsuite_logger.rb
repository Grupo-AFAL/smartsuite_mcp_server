# frozen_string_literal: true

# Configure SmartSuite logger to output to Rails logger
# This enables cache hit/miss and API call logging in the Rails console

require_relative '../../lib/smartsuite/logger'

Rails.application.config.after_initialize do
  SmartSuite::Logger.rails_logger = Rails.logger
  SmartSuite::Logger.level = Rails.env.development? ? :debug : :info
end
