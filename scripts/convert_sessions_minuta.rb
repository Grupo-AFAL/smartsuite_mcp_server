#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to batch convert markdown fields to SmartDoc format
#
# Usage:
#   ruby scripts/convert_sessions_minuta.rb --table-id TABLE_ID --field FIELD_SLUG [options]
#
# Examples:
#   # Convert all records in a table (dry run)
#   ruby scripts/convert_sessions_minuta.rb --table-id 66983fdf0b865a9ad2b02a8d --field description --dry-run
#
#   # Convert records matching a filter
#   ruby scripts/convert_sessions_minuta.rb \
#     --table-id 66983fdf0b865a9ad2b02a8d \
#     --field description \
#     --filter-field s53394fc66 \
#     --filter-value ready_for_review
#
#   # Live run (actually updates records)
#   ruby scripts/convert_sessions_minuta.rb --table-id 66983fdf0b865a9ad2b02a8d --field description

require 'optparse'
require_relative '../lib/smartsuite_client'
require_relative '../lib/smartsuite/formatters/markdown_to_smartdoc'
require 'json'

# Parse command-line options
options = {
  dry_run: false,
  limit: 1000
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: convert_sessions_minuta.rb [options]'
  opts.separator ''
  opts.separator 'Required:'

  opts.on('-t', '--table-id TABLE_ID', 'SmartSuite table ID (required)') do |v|
    options[:table_id] = v
  end

  opts.on('-f', '--field FIELD_SLUG', 'Field slug containing markdown to convert (required)') do |v|
    options[:field] = v
  end

  opts.separator ''
  opts.separator 'Optional filter (to process subset of records):'

  opts.on('--filter-field FIELD_SLUG', 'Field slug to filter by') do |v|
    options[:filter_field] = v
  end

  opts.on('--filter-value VALUE', 'Value to filter for (uses "is" comparison)') do |v|
    options[:filter_value] = v
  end

  opts.on('--filter-comparison OPERATOR', 'Filter comparison operator (default: is)') do |v|
    options[:filter_comparison] = v
  end

  opts.separator ''
  opts.separator 'Options:'

  opts.on('-n', '--dry-run', 'Show what would be converted without making changes') do
    options[:dry_run] = true
  end

  opts.on('-l', '--limit LIMIT', Integer, 'Maximum records to process (default: 1000)') do |v|
    options[:limit] = v
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end

begin
  parser.parse!
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  puts "Error: #{e.message}"
  puts
  puts parser
  exit 1
end

# Validate required arguments
missing = []
missing << '--table-id' unless options[:table_id]
missing << '--field' unless options[:field]

unless missing.empty?
  puts "Error: Missing required arguments: #{missing.join(', ')}"
  puts
  puts parser
  exit 1
end

# Validate filter options (both or neither)
if options[:filter_field] && !options[:filter_value]
  puts 'Error: --filter-field requires --filter-value'
  exit 1
end

if options[:filter_value] && !options[:filter_field]
  puts 'Error: --filter-value requires --filter-field'
  exit 1
end

# Display configuration
puts '=' * 60
puts 'Markdown to SmartDoc Batch Converter'
puts '=' * 60
puts "Mode: #{options[:dry_run] ? 'DRY RUN (no changes will be made)' : 'LIVE'}"
puts "Table ID: #{options[:table_id]}"
puts "Field to convert: #{options[:field]}"
puts "Limit: #{options[:limit]}"
if options[:filter_field]
  comparison = options[:filter_comparison] || 'is'
  puts "Filter: #{options[:filter_field]} #{comparison} '#{options[:filter_value]}'"
end
puts

# Initialize client
api_key = ENV['SMARTSUITE_API_KEY'] || raise('SMARTSUITE_API_KEY not set')
account_id = ENV['SMARTSUITE_ACCOUNT_ID'] || raise('SMARTSUITE_ACCOUNT_ID not set')
client = SmartSuiteClient.new(api_key, account_id)

# Build filter if specified
filter = nil
if options[:filter_field]
  filter = {
    'operator' => 'and',
    'fields' => [
      {
        'field' => options[:filter_field],
        'comparison' => options[:filter_comparison] || 'is',
        'value' => options[:filter_value]
      }
    ]
  }
end

# Fetch records
puts 'Fetching records...'
fetch_options = {
  filter: filter,
  fields: ['title', options[:field]],
  hydrated: true,
  format: :json
}
fetch_options[:filter] = filter if filter

response = client.list_records(
  options[:table_id],
  options[:limit],
  0,
  **fetch_options
)

# Handle different response formats (TOON string vs hash)
if response.is_a?(String)
  puts 'Response is TOON formatted. Parsing...'
  puts response[0..500] # Debug: show first 500 chars
  exit 1
end

records = response['items'] || []
total = records.length

puts "Found #{total} records to process"
puts

# Process each record
converted = 0
skipped = 0
errors = 0
field_slug = options[:field]

records.each_with_index do |record, index|
  id = record['id']
  title = record['title'] || 'Sin título'
  field_value = record[field_slug]

  puts "[#{index + 1}/#{total}] #{title}"

  # Check if field has content
  if field_value.nil? || field_value.empty?
    puts '  → Skipped: No content'
    skipped += 1
    next
  end

  # Check if it's already SmartDoc format (has 'data' key)
  if field_value.is_a?(Hash) && field_value['data']
    puts '  → Skipped: Already in SmartDoc format'
    skipped += 1
    next
  end

  # Extract markdown text
  markdown_text = if field_value.is_a?(Hash) && field_value['html']
                    field_value['html']
                  elsif field_value.is_a?(String)
                    field_value
                  else
                    puts '  → Skipped: Unknown format'
                    skipped += 1
                    next
                  end

  begin
    # Convert to SmartDoc
    smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_text)

    if options[:dry_run]
      puts '  → Would convert (dry run)'
    else
      # Update record
      client.update_record(options[:table_id], id, { field_slug => smartdoc })
      puts '  → Converted successfully'
    end
    converted += 1
  rescue StandardError => e
    puts "  → Error: #{e.message}"
    errors += 1
  end

  # Small delay to avoid rate limiting
  sleep(0.2) unless options[:dry_run]
end

puts
puts '=' * 60
puts 'Summary'
puts '=' * 60
puts "Total processed: #{total}"
puts "Converted: #{converted}"
puts "Skipped: #{skipped}"
puts "Errors: #{errors}"
puts
puts options[:dry_run] ? 'Run without --dry-run to apply changes' : 'Done!'
