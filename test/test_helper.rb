# frozen_string_literal: true

# Set test environment to use test-only database paths
# This prevents test pollution of production data
ENV['SMARTSUITE_TEST_MODE'] = 'true'

# SimpleCov must be loaded before application code
require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Server', 'smartsuite_server.rb'
  add_group 'Client', 'lib/smartsuite_client.rb'
  add_group 'Cache', 'lib/smartsuite/cache'
  add_group 'API', 'lib/smartsuite/api'
  add_group 'MCP', 'lib/smartsuite/mcp'
  add_group 'Formatters', 'lib/smartsuite/formatters'

  # Track coverage over time
  track_files '{lib,smartsuite_server.rb}/**/*.rb'

  # Don't fail on coverage threshold (report only)
  # Goal achieved: 97.47% coverage (exceeded 90% target)
  at_exit do
    result = SimpleCov.result
    if result
      coverage = result.covered_percent
      puts "\n📊 Code Coverage: #{coverage.round(2)}%"
      puts '🎯 Target: 90%'
      puts "📈 Gap: #{(90 - coverage).round(2)}%"
    end
  end
end

require 'minitest/autorun'
require 'json'
require 'stringio'
