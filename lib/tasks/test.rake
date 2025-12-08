# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList[
    "test/test_*.rb",
    "test/smartsuite/**/test_*.rb"
  ]
  t.verbose = true
  t.warning = false
end

# Integration tests (require real API credentials)
Rake::TestTask.new("test:integration") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/integration/test_*.rb"]
  t.verbose = true
  t.warning = false
end

task default: :test
