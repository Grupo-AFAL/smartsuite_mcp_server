# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # Only enable in production (skip dev/test noise)
  config.enabled_environments = %w[production]

  # Breadcrumbs for debugging context
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]

  # Performance monitoring (10% sample rate for production)
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 1).to_f

  # Release tracking (ties errors to deployments)
  config.release = ENV.fetch("GIT_SHA") { `git rev-parse HEAD`.strip rescue nil }

  # Environment name
  config.environment = Rails.env

  # Include PII for debugging (user IPs, emails, etc.)
  config.send_default_pii = true

  # Exclude common noise errors
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActionController::BadRequest"
  ]
end
