# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.0.0'

# SQLite for caching layer
gem 'sqlite3'

# The server uses:
# - json (stdlib)
# - net/http (stdlib)
# - uri (stdlib)
# - time (stdlib)
# - fileutils (stdlib)
# - digest (stdlib)

group :development do
  gem 'reek', require: false
  gem 'rubocop', require: false
  gem 'yard', require: false
end

group :test do
  gem 'minitest'
  gem 'rake'
  gem 'simplecov', require: false
  gem 'webmock', require: false
  # Optional: For testing SecureFileAttacher (uses stub_responses for mocking)
  gem 'aws-sdk-s3', require: false
end
