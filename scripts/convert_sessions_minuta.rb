#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to batch convert markdown Minuta fields to SmartDoc format
# for all sessions with status "Generada automáticamente"

require_relative '../lib/smartsuite_client'
require_relative '../lib/smartsuite/formatters/markdown_to_smartdoc'
require 'json'

# Configuration
TABLE_ID = '66983fdf0b865a9ad2b02a8d' # Sesiones table
STATUS_VALUE = 'ready_for_review'     # "Generada automáticamente" status
MINUTA_FIELD = 'description'          # Minuta field slug
STATUS_FIELD = 's53394fc66'           # Estado autogeneración field slug
DRY_RUN = ARGV.include?('--dry-run')

puts '=' * 60
puts 'Markdown to SmartDoc Batch Converter'
puts '=' * 60
puts "Mode: #{DRY_RUN ? 'DRY RUN (no changes will be made)' : 'LIVE'}"
puts

# Initialize client
api_key = ENV['SMARTSUITE_API_KEY'] || raise('SMARTSUITE_API_KEY not set')
account_id = ENV['SMARTSUITE_ACCOUNT_ID'] || raise('SMARTSUITE_ACCOUNT_ID not set')
client = SmartSuiteClient.new(api_key, account_id)

# Fetch all sessions with "Generada automáticamente" status
puts "Fetching sessions with status 'Generada automáticamente'..."

filter = {
  'operator' => 'and',
  'fields' => [
    {
      'field' => STATUS_FIELD,
      'comparison' => 'is',
      'value' => STATUS_VALUE
    }
  ]
}

# Fetch records (limit high to get all)
response = client.list_records(
  TABLE_ID,
  1000,  # limit
  0,     # offset
  filter: filter,
  fields: ['title', MINUTA_FIELD, STATUS_FIELD],
  hydrated: true,
  format: :json
)

# Handle different response formats (TOON string vs hash)
if response.is_a?(String)
  puts 'Response is TOON formatted. Parsing...'
  puts response[0..500] # Debug: show first 500 chars
  exit 1
end

records = response['items'] || []
total = records.length

puts "Found #{total} sessions to process"
puts

# Process each record
converted = 0
skipped = 0
errors = 0

records.each_with_index do |record, index|
  id = record['id']
  title = record['title'] || 'Sin título'
  minuta = record[MINUTA_FIELD]

  puts "[#{index + 1}/#{total}] #{title}"

  # Check if minuta has content
  if minuta.nil? || minuta.empty?
    puts '  → Skipped: No minuta content'
    skipped += 1
    next
  end

  # Check if it's already SmartDoc format (has 'data' key)
  if minuta.is_a?(Hash) && minuta['data']
    puts '  → Skipped: Already in SmartDoc format'
    skipped += 1
    next
  end

  # Extract markdown text
  markdown_text = if minuta.is_a?(Hash) && minuta['html']
                    minuta['html']
                  elsif minuta.is_a?(String)
                    minuta
                  else
                    puts '  → Skipped: Unknown format'
                    skipped += 1
                    next
                  end

  begin
    # Convert to SmartDoc
    smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown_text)

    if DRY_RUN
      puts '  → Would convert (dry run)'
    else
      # Update record
      client.update_record(TABLE_ID, id, { MINUTA_FIELD => smartdoc })
      puts '  → Converted successfully'
    end
    converted += 1
  rescue StandardError => e
    puts "  → Error: #{e.message}"
    errors += 1
  end

  # Small delay to avoid rate limiting
  sleep(0.2) unless DRY_RUN
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
puts DRY_RUN ? 'Run without --dry-run to apply changes' : 'Done!'
