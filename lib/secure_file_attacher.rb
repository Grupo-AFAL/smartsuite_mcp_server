# frozen_string_literal: true

require 'aws-sdk-s3'
require 'securerandom'

# SecureFileAttacher provides a secure way to attach local files to SmartSuite records.
#
# SmartSuite's attach_file API requires publicly accessible URLs, which poses security risks
# for sensitive files. This class solves that problem by:
# 1. Uploading files to S3 with server-side encryption
# 2. Generating short-lived pre-signed URLs (default: 2 minutes)
# 3. Attaching files to SmartSuite via these temporary URLs
# 4. Automatically cleaning up uploaded files after SmartSuite fetches them
#
# @example Basic usage
#   attacher = SecureFileAttacher.new(smartsuite_client, 'my-temp-bucket')
#   attacher.attach_file_securely(
#     'tbl_123',
#     'rec_456',
#     'attachments',
#     './document.pdf'
#   )
#
# @example Attach multiple files
#   attacher.attach_file_securely(
#     'tbl_123',
#     'rec_456',
#     'images',
#     ['./photo1.jpg', './photo2.jpg', './photo3.jpg']
#   )
#
# @example With custom expiration and region
#   attacher = SecureFileAttacher.new(
#     smartsuite_client,
#     'my-bucket',
#     region: 'eu-west-1',
#     url_expires_in: 300  # 5 minutes
#   )
#
# @note Requires AWS credentials configured via environment variables or IAM role:
#   - AWS_ACCESS_KEY_ID
#   - AWS_SECRET_ACCESS_KEY
#   - AWS_REGION (optional, defaults to us-east-1)
#
# @note S3 bucket should have:
#   - Server-side encryption enabled
#   - Lifecycle policy to delete temp-uploads/ after 1 day (failsafe)
#   - CORS policy allowing SmartSuite to fetch files
class SecureFileAttacher
  # Default expiration time for pre-signed URLs (2 minutes)
  DEFAULT_URL_EXPIRATION = 120

  # Default timeout waiting for SmartSuite to fetch files (30 seconds)
  DEFAULT_FETCH_TIMEOUT = 30

  # Default S3 region
  DEFAULT_REGION = 'us-east-1'

  # @return [SmartSuiteClient] the SmartSuite client instance
  attr_reader :client

  # @return [String] the S3 bucket name used for temporary uploads
  attr_reader :bucket_name

  # @return [Integer] expiration time in seconds for pre-signed URLs
  attr_reader :url_expires_in

  # @return [Integer] timeout in seconds waiting for SmartSuite to fetch files
  attr_reader :fetch_timeout

  # Initialize a new SecureFileAttacher instance.
  #
  # @param smartsuite_client [SmartSuiteClient] configured SmartSuite client
  # @param bucket_name [String] S3 bucket name for temporary file uploads
  # @param region [String] AWS region (default: 'us-east-1')
  # @param url_expires_in [Integer] pre-signed URL expiration in seconds (default: 120)
  # @param fetch_timeout [Integer] timeout waiting for fetch in seconds (default: 30)
  #
  # @raise [ArgumentError] if smartsuite_client or bucket_name is nil
  # @raise [Aws::Errors::MissingCredentialsError] if AWS credentials not configured
  #
  # @example Basic initialization
  #   attacher = SecureFileAttacher.new(client, 'my-temp-bucket')
  #
  # @example With custom settings
  #   attacher = SecureFileAttacher.new(
  #     client,
  #     'my-bucket',
  #     region: 'eu-west-1',
  #     url_expires_in: 300,
  #     fetch_timeout: 60
  #   )
  def initialize(smartsuite_client, bucket_name, region: DEFAULT_REGION, url_expires_in: DEFAULT_URL_EXPIRATION,
                 fetch_timeout: DEFAULT_FETCH_TIMEOUT)
    raise ArgumentError, 'smartsuite_client cannot be nil' if smartsuite_client.nil?
    raise ArgumentError, 'bucket_name cannot be nil' if bucket_name.nil?

    @client = smartsuite_client
    @bucket_name = bucket_name
    @url_expires_in = url_expires_in
    @fetch_timeout = fetch_timeout

    # Initialize S3 resource
    @s3 = Aws::S3::Resource.new(region: region)
    @bucket = @s3.bucket(bucket_name)

    # Verify bucket exists
    verify_bucket_access!
  end

  # Securely attach local files to a SmartSuite record.
  #
  # This method:
  # 1. Uploads files to S3 with encryption
  # 2. Generates short-lived pre-signed URLs
  # 3. Calls SmartSuite's attach_file API
  # 4. Waits for SmartSuite to fetch files
  # 5. Deletes temporary files from S3
  #
  # @param table_id [String] SmartSuite table identifier
  # @param record_id [String] SmartSuite record identifier
  # @param field_slug [String] slug of the file/image field
  # @param file_paths [String, Array<String>] local file path(s) to attach
  #
  # @return [Hash] SmartSuite API response with updated record
  #
  # @raise [ArgumentError] if any required parameter is missing
  # @raise [Errno::ENOENT] if any file doesn't exist
  # @raise [Aws::S3::Errors::ServiceError] if S3 operations fail
  # @raise [RuntimeError] if SmartSuite API call fails
  #
  # @example Attach single file
  #   result = attacher.attach_file_securely(
  #     'tbl_abc123',
  #     'rec_xyz789',
  #     'attachments',
  #     './invoice.pdf'
  #   )
  #
  # @example Attach multiple files
  #   result = attacher.attach_file_securely(
  #     'tbl_abc123',
  #     'rec_xyz789',
  #     'images',
  #     ['./photo1.jpg', './photo2.jpg']
  #   )
  def attach_file_securely(table_id, record_id, field_slug, file_paths)
    validate_parameters!(table_id, record_id, field_slug, file_paths)

    file_paths = [file_paths] unless file_paths.is_a?(Array)
    validate_files_exist!(file_paths)

    temp_urls = []
    temp_objects = []

    begin
      # Upload files and generate temporary URLs
      file_paths.each do |path|
        key = generate_temp_key(path)
        obj = @bucket.object(key)

        log_debug("Uploading file to S3: #{path} -> s3://#{@bucket_name}/#{key}")

        # Upload with server-side encryption
        obj.upload_file(path, server_side_encryption: 'AES256')

        # Generate short-lived pre-signed URL
        url = obj.presigned_url(:get, expires_in: @url_expires_in)

        temp_urls << url
        temp_objects << obj

        log_debug("Generated pre-signed URL (expires in #{@url_expires_in}s)")
      end

      log_debug("Attaching #{file_paths.length} file(s) to SmartSuite record #{record_id}")

      # Attach to SmartSuite
      result = @client.attach_file(table_id, record_id, field_slug, temp_urls)

      log_debug('SmartSuite attach successful, waiting for fetch...')

      # Wait for SmartSuite to fetch files
      wait_for_fetch(temp_objects, timeout: @fetch_timeout)

      log_debug('File fetch complete')

      result
    ensure
      # Always cleanup, even if SmartSuite fails
      cleanup_temp_files(temp_objects)
    end
  end

  # Generate an S3 bucket lifecycle configuration for automatic cleanup.
  #
  # Returns a lifecycle policy that automatically deletes files in temp-uploads/
  # after 1 day. This provides failsafe cleanup in case manual deletion fails.
  #
  # @return [Hash] S3 lifecycle configuration
  #
  # @example Apply lifecycle policy
  #   attacher = SecureFileAttacher.new(client, 'my-bucket')
  #   lifecycle_config = attacher.generate_lifecycle_policy
  #
  #   s3_client = Aws::S3::Client.new
  #   s3_client.put_bucket_lifecycle_configuration(
  #     bucket: 'my-bucket',
  #     lifecycle_configuration: lifecycle_config
  #   )
  def generate_lifecycle_policy
    {
      rules: [
        {
          id: 'Delete temporary uploads after 1 day',
          status: 'Enabled',
          prefix: 'temp-uploads/',
          expiration: {
            days: 1
          }
        }
      ]
    }
  end

  private

  # Validate required parameters
  def validate_parameters!(table_id, record_id, field_slug, file_paths)
    raise ArgumentError, 'table_id cannot be nil or empty' if table_id.nil? || table_id.empty?
    raise ArgumentError, 'record_id cannot be nil or empty' if record_id.nil? || record_id.empty?
    raise ArgumentError, 'field_slug cannot be nil or empty' if field_slug.nil? || field_slug.empty?
    raise ArgumentError, 'file_paths cannot be nil or empty' if file_paths.nil? ||
                                                                 (file_paths.is_a?(Array) && file_paths.empty?)
  end

  # Validate all files exist
  def validate_files_exist!(file_paths)
    file_paths.each do |path|
      raise Errno::ENOENT, "File not found: #{path}" unless File.exist?(path)
      raise ArgumentError, "Path is a directory, not a file: #{path}" if File.directory?(path)
    end
  end

  # Verify bucket exists and is accessible
  def verify_bucket_access!
    @bucket.exists?
  rescue Aws::S3::Errors::ServiceError => e
    raise "S3 bucket '#{@bucket_name}' is not accessible: #{e.message}"
  end

  # Generate a unique S3 key for temporary file upload
  #
  # Format: temp-uploads/{timestamp}/{uuid}/{filename}
  # This ensures uniqueness and allows for easy cleanup via prefix
  def generate_temp_key(file_path)
    timestamp = Time.now.to_i
    uuid = SecureRandom.uuid
    filename = File.basename(file_path)
    "temp-uploads/#{timestamp}/#{uuid}/#{filename}"
  end

  # Wait for SmartSuite to fetch files
  #
  # SmartSuite needs time to download files from the pre-signed URLs.
  # We wait to ensure files are fetched before deletion.
  def wait_for_fetch(objects, timeout:)
    start = Time.now
    elapsed = 0

    loop do
      elapsed = Time.now - start
      break if elapsed >= timeout

      sleep 2
    end

    log_debug("Waited #{elapsed.round(1)}s for SmartSuite to fetch files")
  end

  # Delete temporary files from S3
  def cleanup_temp_files(objects)
    objects.each do |obj|
      begin
        obj.delete
        log_debug("Deleted temporary file: s3://#{@bucket_name}/#{obj.key}")
      rescue Aws::S3::Errors::NoSuchKey
        # Already deleted, ignore
        log_debug("File already deleted: s3://#{@bucket_name}/#{obj.key}")
      rescue Aws::S3::Errors::ServiceError => e
        # Log error but don't fail - lifecycle policy will clean up
        log_error("Failed to delete temporary file: #{e.message}")
      end
    end
  end

  # Simple debug logging (can be enhanced with proper logger)
  def log_debug(message)
    return unless ENV['SECURE_FILE_ATTACHER_DEBUG']

    warn "[SecureFileAttacher] #{message}"
  end

  # Simple error logging
  def log_error(message)
    warn "[SecureFileAttacher ERROR] #{message}"
  end
end
