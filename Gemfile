# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.1.0"

# Rails framework
gem "rails", "~> 8.1.2"

# PostgreSQL for database (replaces SQLite for hosted version)
gem "pg", "~> 1.6"

# Keep SQLite for local/stdio mode compatibility
gem "sqlite3"

# Puma web server
gem "puma", ">= 5.0"

# Token-optimized formatting for LLM responses
gem "toon-ruby"

# Concurrent data structures for SSE connections
gem "concurrent-ruby"

# Windows timezone data
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching
gem "bootsnap", require: false

# Deploy with Kamal
gem "kamal", require: false

# HTTP asset caching/compression for Puma
gem "thruster", require: false

# CORS for cross-origin requests (needed for SSE from different domains)
gem "rack-cors"

# Error monitoring
gem "sentry-ruby"
gem "sentry-rails"

group :development do
  gem "lefthook", require: false
  gem "reek", require: false
  gem "rubocop", require: false
  gem "rubocop-rails-omakase", require: false
  gem "yard", require: false
end

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
end

group :test do
  gem "minitest"
  gem "minitest-mock"
  gem "rake"
  gem "simplecov", require: false
  gem "webmock", require: false
  gem "aws-sdk-s3", require: false
end
