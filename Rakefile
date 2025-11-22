# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  # Include all test files except integration tests (which require real credentials)
  t.test_files = FileList['test/**/test_*.rb'].exclude('test/integration/**/*')
  t.verbose = true
  # Disable Ruby warnings to suppress bundler/rubygems constant redefinition warnings
  t.warning = false
end

task default: :test
