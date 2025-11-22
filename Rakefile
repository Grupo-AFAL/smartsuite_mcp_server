# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
  # Disable Ruby warnings to suppress bundler/rubygems constant redefinition warnings
  t.warning = false
end

task default: :test
