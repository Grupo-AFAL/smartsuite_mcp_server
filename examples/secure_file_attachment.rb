#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Securely Attach Local Files to SmartSuite Records
#
# This example demonstrates how to safely attach local files to SmartSuite records
# without making them publicly accessible. It uses AWS S3 with short-lived pre-signed
# URLs to provide temporary access only to SmartSuite.
#
# Prerequisites:
# 1. AWS account with S3 bucket created
# 2. AWS credentials configured (environment variables or ~/.aws/credentials)
# 3. SmartSuite API credentials
# 4. aws-sdk-s3 gem installed: gem install aws-sdk-s3

require_relative '../lib/smartsuite_client'
require_relative '../lib/secure_file_attacher'

# Configuration
SMARTSUITE_API_KEY = ENV.fetch('SMARTSUITE_API_KEY')
SMARTSUITE_ACCOUNT_ID = ENV.fetch('SMARTSUITE_ACCOUNT_ID')
S3_BUCKET_NAME = ENV.fetch('S3_TEMP_BUCKET', 'my-smartsuite-temp-uploads')

# AWS credentials are automatically loaded from:
# - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)
# - ~/.aws/credentials file
# - IAM instance profile (if running on EC2)

puts '=' * 80
puts 'Secure File Attachment Example'
puts '=' * 80
puts

# ==============================================================================
# Example 1: Attach a Single File
# ==============================================================================

puts '1. Attaching a single PDF file...'

begin
  # Initialize SmartSuite client
  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)

  # Initialize secure file attacher
  attacher = SecureFileAttacher.new(
    client,
    S3_BUCKET_NAME,
    region: 'us-east-1', # Your S3 region
    url_expires_in: 120,         # 2 minutes (default)
    fetch_timeout: 30            # 30 seconds (default)
  )

  # Attach a single file
  result = attacher.attach_file_securely(
    'tbl_6796989a7ee3c6b731717836',  # Your table ID
    'rec_68e3d5fb98c0282a4f1e2614',  # Your record ID
    'attachments',                    # Field slug for file field
    './invoice.pdf'                   # Local file path
  )

  puts '✓ File attached successfully!'
  puts "  Record ID: #{result['id']}"
  puts "  Attachments: #{result['attachments']&.length || 0} file(s)"
  puts
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts "  #{e.backtrace.first}"
  puts
end

# ==============================================================================
# Example 2: Attach Multiple Files at Once
# ==============================================================================

puts '2. Attaching multiple image files...'

begin
  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)
  attacher = SecureFileAttacher.new(client, S3_BUCKET_NAME)

  # Attach multiple files to a single field
  result = attacher.attach_file_securely(
    'tbl_6796989a7ee3c6b731717836',
    'rec_68e3d5fb98c0282a4f1e2614',
    'images',
    [
      './photo1.jpg',
      './photo2.jpg',
      './photo3.png'
    ]
  )

  puts '✓ Files attached successfully!'
  puts "  Record ID: #{result['id']}"
  puts "  Images: #{result['images']&.length || 0} file(s)"
  puts
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts
end

# ==============================================================================
# Example 3: With Custom Expiration (More Secure)
# ==============================================================================

puts '3. Attaching with ultra-short expiration (60 seconds)...'

begin
  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)

  # Use shorter expiration for extra security
  attacher = SecureFileAttacher.new(
    client,
    S3_BUCKET_NAME,
    url_expires_in: 60 # 1 minute only
  )

  attacher.attach_file_securely(
    'tbl_6796989a7ee3c6b731717836',
    'rec_68e3d5fb98c0282a4f1e2614',
    'documents',
    './sensitive_document.pdf'
  )

  puts '✓ Sensitive file attached with 60-second URL expiration!'
  puts
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts
end

# ==============================================================================
# Example 4: With Debug Logging Enabled
# ==============================================================================

puts '4. Attaching with debug logging enabled...'

begin
  # Enable debug logging
  ENV['SECURE_FILE_ATTACHER_DEBUG'] = 'true'

  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)
  attacher = SecureFileAttacher.new(client, S3_BUCKET_NAME)

  attacher.attach_file_securely(
    'tbl_6796989a7ee3c6b731717836',
    'rec_68e3d5fb98c0282a4f1e2614',
    'attachments',
    './document.pdf'
  )

  puts '✓ File attached with detailed logging!'
  puts
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts
ensure
  ENV.delete('SECURE_FILE_ATTACHER_DEBUG')
end

# ==============================================================================
# Example 5: Setting Up S3 Bucket Lifecycle Policy
# ==============================================================================

puts '5. Generating S3 lifecycle policy for automatic cleanup...'
puts

begin
  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)
  attacher = SecureFileAttacher.new(client, S3_BUCKET_NAME)

  # Generate lifecycle policy
  lifecycle_policy = attacher.generate_lifecycle_policy

  puts 'Generated lifecycle policy:'
  puts JSON.pretty_generate(lifecycle_policy)
  puts
  puts 'To apply this policy, run:'
  puts
  puts '  aws s3api put-bucket-lifecycle-configuration \\'
  puts "    --bucket #{S3_BUCKET_NAME} \\"
  puts '    --lifecycle-configuration file://lifecycle.json'
  puts
  puts 'This ensures temporary files are deleted after 1 day (failsafe cleanup).'
  puts
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts
end

# ==============================================================================
# Example 6: Error Handling Best Practices
# ==============================================================================

puts '6. Demonstrating comprehensive error handling...'
puts

begin
  client = SmartSuiteClient.new(SMARTSUITE_API_KEY, SMARTSUITE_ACCOUNT_ID)
  attacher = SecureFileAttacher.new(client, S3_BUCKET_NAME)

  # This will fail because the file doesn't exist
  attacher.attach_file_securely(
    'tbl_6796989a7ee3c6b731717836',
    'rec_68e3d5fb98c0282a4f1e2614',
    'attachments',
    './nonexistent_file.pdf'
  )
rescue Errno::ENOENT => e
  puts "✗ File not found: #{e.message}"
  puts '  → Check that the file path is correct'
  puts
rescue ArgumentError => e
  puts "✗ Invalid parameter: #{e.message}"
  puts '  → Check that all required parameters are provided'
  puts
rescue Aws::S3::Errors::ServiceError => e
  puts "✗ S3 error: #{e.message}"
  puts '  → Check AWS credentials and bucket permissions'
  puts
rescue RuntimeError => e
  puts "✗ SmartSuite API error: #{e.message}"
  puts '  → Check SmartSuite credentials and record permissions'
  puts
rescue StandardError => e
  puts "✗ Unexpected error: #{e.class} - #{e.message}"
  puts "  #{e.backtrace.first}"
  puts
end

# ==============================================================================
# Security Best Practices
# ==============================================================================

puts '=' * 80
puts 'Security Best Practices'
puts '=' * 80
puts
puts '1. Use short expiration times (60-120 seconds)'
puts '2. Enable S3 server-side encryption (done automatically)'
puts '3. Set up S3 lifecycle policy for failsafe cleanup'
puts '4. Use separate S3 bucket for temporary files'
puts '5. Configure S3 bucket CORS to allow SmartSuite domains only'
puts '6. Use IAM roles with minimal permissions (GetObject, PutObject, DeleteObject)'
puts '7. Monitor S3 access logs for unusual activity'
puts '8. Never commit AWS credentials to version control'
puts
puts '=' * 80
puts 'Setup Complete!'
puts '=' * 80
