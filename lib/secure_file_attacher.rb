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
                 fetch_timeout: DEFAULT_FETCH_TIMEOUT, profile: nil)
    raise ArgumentError, 'smartsuite_client cannot be nil' if smartsuite_client.nil?
    raise ArgumentError, 'bucket_name cannot be nil' if bucket_name.nil?

    @client = smartsuite_client
    @bucket_name = bucket_name
    @url_expires_in = url_expires_in
    @fetch_timeout = fetch_timeout

    # Initialize S3 resource with optional profile for credential isolation
    s3_options = { region: region }
    s3_options[:profile] = profile if profile

    # Disable SSL verification - same approach as SmartSuite HttpClient
    # Avoids certificate issues common on macOS
    s3_options[:ssl_verify_peer] = false

    @s3 = Aws::S3::Resource.new(**s3_options)
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
        file_size = File.size(path)

        log_s3('UPLOAD', "#{File.basename(path)} (#{format_size(file_size)}) -> s3://#{@bucket_name}/#{key}")

        # Upload with server-side encryption
        # Using put with File.open instead of deprecated upload_file
        File.open(path, 'rb') do |file|
          obj.put(body: file, server_side_encryption: 'AES256')
        end

        log_s3('UPLOAD_COMPLETE', "#{File.basename(path)} uploaded successfully")

        # Generate short-lived pre-signed URL
        url = obj.presigned_url(:get, expires_in: @url_expires_in)

        temp_urls << url
        temp_objects << obj

        log_s3('PRESIGN', "Generated URL for #{File.basename(path)} (expires in #{@url_expires_in}s)")
      end

      log_s3('ATTACH', "Sending #{file_paths.length} file(s) to SmartSuite record #{record_id}")

      # Attach to SmartSuite
      result = @client.attach_file(table_id, record_id, field_slug, temp_urls)

      log_s3('ATTACH_COMPLETE', "SmartSuite accepted #{file_paths.length} file(s)")

      # Wait for SmartSuite to fetch files
      log_s3('WAIT', "Waiting #{@fetch_timeout}s for SmartSuite to fetch files...")
      wait_for_fetch(temp_objects, timeout: @fetch_timeout)

      log_s3('WAIT_COMPLETE', 'Fetch period complete')

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
  def wait_for_fetch(_objects, timeout:)
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
    return if objects.empty?

    log_s3('CLEANUP', "Deleting #{objects.length} temporary file(s) from S3")

    objects.each do |obj|
      obj.delete
      log_s3('DELETE', "Deleted s3://#{@bucket_name}/#{obj.key}")
    rescue Aws::S3::Errors::NoSuchKey
      # Already deleted, ignore
      log_s3('DELETE_SKIP', "Already deleted: #{obj.key}")
    rescue Aws::S3::Errors::ServiceError => e
      # Log error but don't fail - lifecycle policy will clean up
      log_error("Failed to delete #{obj.key}: #{e.message}")
    end

    log_s3('CLEANUP_COMPLETE', 'Temporary files cleaned up')
  end

  # Format file size in human-readable format
  def format_size(bytes)
    return '0 B' if bytes.zero?

    units = %w[B KB MB GB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min
    format('%<size>.1f %<unit>s', size: bytes.to_f / (1024**exp), unit: units[exp])
  end

  # Simple debug logging (can be enhanced with proper logger)
  def log_debug(message)
    return unless ENV['SECURE_FILE_ATTACHER_DEBUG']

    warn "[SecureFileAttacher] #{message}"
  end

  # S3 action logging - uses client's log_metric for consistent logging
  def log_s3(action, message)
    formatted = "☁️  [S3] #{action}: #{message}"
    # Use client's log_metric if available, otherwise fallback to stderr
    if @client.respond_to?(:log_metric)
      @client.log_metric(formatted)
    else
      warn "[SecureFileAttacher S3] #{action}: #{message}"
    end
  end

  # Simple error logging
  def log_error(message)
    warn "[SecureFileAttacher ERROR] #{message}"
  end
end
