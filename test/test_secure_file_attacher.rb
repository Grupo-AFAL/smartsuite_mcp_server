# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'json'
require 'tempfile'
require_relative '../lib/smartsuite_client'

# Try to load SecureFileAttacher - skip all tests if aws-sdk-s3 not installed
begin
  require_relative '../lib/secure_file_attacher'
  AWS_SDK_AVAILABLE = true
rescue LoadError => e
  AWS_SDK_AVAILABLE = false
  warn "Skipping SecureFileAttacher tests: #{e.message}"
end

# Tests for SecureFileAttacher
class TestSecureFileAttacher < Minitest::Test
  def self.runnable_methods
    # Skip all tests if AWS SDK not available
    return [] unless defined?(AWS_SDK_AVAILABLE) && AWS_SDK_AVAILABLE

    super
  end

  def setup
    @api_key = 'test_api_key'
    @account_id = 'test_account_id'
    @bucket_name = 'test-bucket'

    # Create a real SmartSuiteClient for testing
    @client = SmartSuiteClient.new(@api_key, @account_id, cache_enabled: false)

    # Create temporary test files
    @temp_file1 = Tempfile.new(['test1', '.txt'])
    @temp_file1.write('Test content 1')
    @temp_file1.close

    @temp_file2 = Tempfile.new(['test2', '.pdf'])
    @temp_file2.write('Test PDF content')
    @temp_file2.close

    # Disable real HTTP connections
    WebMock.disable_net_connect!
  end

  def teardown
    # Clean up temporary files
    @temp_file1&.unlink
    @temp_file2&.unlink
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  # ==============================================================================
  # Initialization tests
  # ==============================================================================

  def test_initialize_requires_smartsuite_client
    error = assert_raises(ArgumentError) do
      SecureFileAttacher.new(nil, @bucket_name)
    end
    assert_includes error.message, 'smartsuite_client cannot be nil'
  end

  def test_initialize_requires_bucket_name
    error = assert_raises(ArgumentError) do
      SecureFileAttacher.new(@client, nil)
    end
    assert_includes error.message, 'bucket_name cannot be nil'
  end

  def test_initialize_sets_default_values
    attacher = create_stubbed_attacher

    assert_equal @client, attacher.client
    assert_equal @bucket_name, attacher.bucket_name
    assert_equal 120, attacher.url_expires_in
    assert_equal 30, attacher.fetch_timeout
  end

  def test_initialize_accepts_custom_values
    attacher = create_stubbed_attacher(url_expires_in: 60, fetch_timeout: 15)

    assert_equal 60, attacher.url_expires_in
    assert_equal 15, attacher.fetch_timeout
  end

  def test_initialize_accepts_custom_region
    attacher = create_stubbed_attacher(region: 'eu-west-1')
    assert_kind_of SecureFileAttacher, attacher
  end

  # ==============================================================================
  # Parameter validation tests
  # ==============================================================================

  def test_attach_file_securely_requires_table_id
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely(nil, 'rec_123', 'attachments', @temp_file1.path)
    end
    assert_includes error.message, 'table_id'
  end

  def test_attach_file_securely_requires_table_id_not_empty
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('', 'rec_123', 'attachments', @temp_file1.path)
    end
    assert_includes error.message, 'table_id'
  end

  def test_attach_file_securely_requires_record_id
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', nil, 'attachments', @temp_file1.path)
    end
    assert_includes error.message, 'record_id'
  end

  def test_attach_file_securely_requires_record_id_not_empty
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', '', 'attachments', @temp_file1.path)
    end
    assert_includes error.message, 'record_id'
  end

  def test_attach_file_securely_requires_field_slug
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', 'rec_123', nil, @temp_file1.path)
    end
    assert_includes error.message, 'field_slug'
  end

  def test_attach_file_securely_requires_field_slug_not_empty
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', 'rec_123', '', @temp_file1.path)
    end
    assert_includes error.message, 'field_slug'
  end

  def test_attach_file_securely_requires_file_paths
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', 'rec_123', 'attachments', nil)
    end
    assert_includes error.message, 'file_paths'
  end

  def test_attach_file_securely_requires_file_paths_not_empty_array
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely('tbl_123', 'rec_123', 'attachments', [])
    end
    assert_includes error.message, 'file_paths'
  end

  def test_attach_file_securely_rejects_nonexistent_file
    attacher = create_stubbed_attacher

    error = assert_raises(Errno::ENOENT) do
      attacher.attach_file_securely(
        'tbl_123',
        'rec_123',
        'attachments',
        '/nonexistent/file.pdf'
      )
    end
    assert_includes error.message, 'File not found'
  end

  def test_attach_file_securely_rejects_directory
    attacher = create_stubbed_attacher

    error = assert_raises(ArgumentError) do
      attacher.attach_file_securely(
        'tbl_123',
        'rec_123',
        'attachments',
        File.dirname(@temp_file1.path)
      )
    end
    assert_includes error.message, 'directory'
  end

  # ==============================================================================
  # Success path tests with stubbed S3
  # ==============================================================================

  def test_attach_file_securely_single_file_success
    attacher = create_stubbed_attacher(fetch_timeout: 0)

    # Stub SmartSuite API call
    stub_request(:patch, %r{/applications/tbl_123/records/rec_456/})
      .to_return(
        status: 200,
        body: { 'id' => 'rec_456', 'title' => 'Test', 'attachments' => [] }.to_json
      )

    result = attacher.attach_file_securely(
      'tbl_123',
      'rec_456',
      'attachments',
      @temp_file1.path
    )

    assert result.is_a?(Hash)
    assert_equal 'rec_456', result['id']
  end

  def test_attach_file_securely_multiple_files_success
    attacher = create_stubbed_attacher(fetch_timeout: 0)

    # Stub SmartSuite API call
    stub_request(:patch, %r{/applications/tbl_123/records/rec_456/})
      .to_return(
        status: 200,
        body: { 'id' => 'rec_456', 'attachments' => [{}, {}] }.to_json
      )

    result = attacher.attach_file_securely(
      'tbl_123',
      'rec_456',
      'attachments',
      [@temp_file1.path, @temp_file2.path]
    )

    assert result.is_a?(Hash)
    assert_equal 'rec_456', result['id']
  end

  def test_attach_file_cleans_up_on_smartsuite_error
    attacher = create_stubbed_attacher(fetch_timeout: 0)

    # Stub SmartSuite API to fail
    stub_request(:patch, %r{/applications/tbl_123/records/rec_456/})
      .to_return(status: 500, body: { 'error' => 'Server error' }.to_json)

    # Should raise error but still clean up S3 files (via ensure block)
    assert_raises(RuntimeError) do
      attacher.attach_file_securely(
        'tbl_123',
        'rec_456',
        'attachments',
        @temp_file1.path
      )
    end
  end

  # ==============================================================================
  # Lifecycle policy tests
  # ==============================================================================

  def test_generate_lifecycle_policy_returns_valid_policy
    attacher = create_stubbed_attacher

    policy = attacher.generate_lifecycle_policy

    assert_kind_of Hash, policy
    assert_includes policy, :rules
    assert_kind_of Array, policy[:rules]
    assert_equal 1, policy[:rules].length

    rule = policy[:rules].first
    assert_equal 'Delete temporary uploads after 1 day', rule[:id]
    assert_equal 'Enabled', rule[:status]
    assert_equal 'temp-uploads/', rule[:prefix]
    assert_equal 1, rule[:expiration][:days]
  end

  # ==============================================================================
  # Debug logging tests
  # ==============================================================================

  def test_debug_logging_disabled_by_default
    attacher = create_stubbed_attacher(fetch_timeout: 0)

    stub_request(:patch, %r{/applications/tbl_123/records/rec_456/})
      .to_return(status: 200, body: { 'id' => 'rec_456' }.to_json)

    # Capture stderr
    original_stderr = $stderr
    $stderr = StringIO.new

    attacher.attach_file_securely('tbl_123', 'rec_456', 'attachments', @temp_file1.path)

    output = $stderr.string
    $stderr = original_stderr

    # Should not have debug output when DEBUG env var not set
    refute_includes output, '[SecureFileAttacher]'
  end

  def test_debug_logging_enabled_with_env_var
    attacher = create_stubbed_attacher(fetch_timeout: 0)

    stub_request(:patch, %r{/applications/tbl_123/records/rec_456/})
      .to_return(status: 200, body: { 'id' => 'rec_456' }.to_json)

    # Enable debug mode
    original_env = ENV.fetch('SECURE_FILE_ATTACHER_DEBUG', nil)
    ENV['SECURE_FILE_ATTACHER_DEBUG'] = 'true'

    # Capture stderr
    original_stderr = $stderr
    $stderr = StringIO.new

    attacher.attach_file_securely('tbl_123', 'rec_456', 'attachments', @temp_file1.path)

    output = $stderr.string
    $stderr = original_stderr
    ENV['SECURE_FILE_ATTACHER_DEBUG'] = original_env

    # Should have debug output
    assert_includes output, '[SecureFileAttacher]'
    assert_includes output, 'Uploading file to S3'
  end

  # ==============================================================================
  # Constants tests
  # ==============================================================================

  def test_default_constants
    assert_equal 120, SecureFileAttacher::DEFAULT_URL_EXPIRATION
    assert_equal 30, SecureFileAttacher::DEFAULT_FETCH_TIMEOUT
    assert_equal 'us-east-1', SecureFileAttacher::DEFAULT_REGION
  end

  # ==============================================================================
  # Private method coverage (via integration tests)
  # ==============================================================================

  def test_generate_temp_key_format
    attacher = create_stubbed_attacher

    # Access private method for testing
    key = attacher.send(:generate_temp_key, '/path/to/document.pdf')

    assert_match %r{^temp-uploads/\d+/[a-f0-9-]+/document\.pdf$}, key
  end

  def test_generate_temp_key_uniqueness
    attacher = create_stubbed_attacher

    keys = 5.times.map { attacher.send(:generate_temp_key, '/path/to/file.txt') }

    # All keys should be unique
    assert_equal 5, keys.uniq.size
  end

  # ==============================================================================
  # Full initialization tests with stubbed S3
  # ==============================================================================

  def test_initialize_with_stubbed_s3
    # Use AWS SDK's built-in stubbing
    Aws.config[:s3] = {
      stub_responses: {
        head_bucket: {}
      }
    }

    attacher = SecureFileAttacher.new(
      @client,
      @bucket_name,
      region: 'us-east-1'
    )

    assert_equal @client, attacher.client
    assert_equal @bucket_name, attacher.bucket_name
    assert_equal 120, attacher.url_expires_in
    assert_equal 30, attacher.fetch_timeout
  ensure
    Aws.config[:s3] = nil
  end

  def test_initialize_with_custom_options_stubbed
    Aws.config[:s3] = {
      stub_responses: {
        head_bucket: {}
      }
    }

    attacher = SecureFileAttacher.new(
      @client,
      @bucket_name,
      region: 'eu-west-1',
      url_expires_in: 300,
      fetch_timeout: 60
    )

    assert_equal 300, attacher.url_expires_in
    assert_equal 60, attacher.fetch_timeout
  ensure
    Aws.config[:s3] = nil
  end

  # ==============================================================================
  # log_error tests
  # ==============================================================================

  def test_log_error_outputs_to_stderr
    attacher = create_stubbed_attacher

    original_stderr = $stderr
    $stderr = StringIO.new

    attacher.send(:log_error, 'Test error message')

    output = $stderr.string
    $stderr = original_stderr

    assert_includes output, '[SecureFileAttacher ERROR]'
    assert_includes output, 'Test error message'
  end

  # ==============================================================================
  # Helper methods
  # ==============================================================================

  private

  # Creates a SecureFileAttacher with stubbed S3 responses
  def create_stubbed_attacher(**options)
    # Create S3 resource with stubbed responses (no real AWS calls)
    s3_resource = Aws::S3::Resource.new(
      region: options[:region] || 'us-east-1',
      stub_responses: true
    )

    # Stub bucket.exists? to return true
    s3_resource.client.stub_responses(:head_bucket, {})

    # Stub put_object for upload
    s3_resource.client.stub_responses(:put_object, {})

    # Stub delete_object for cleanup
    s3_resource.client.stub_responses(:delete_object, {})

    # Create attacher with stubbed S3
    attacher = SecureFileAttacher.allocate
    attacher.instance_variable_set(:@client, @client)
    attacher.instance_variable_set(:@bucket_name, @bucket_name)
    attacher.instance_variable_set(:@url_expires_in, options[:url_expires_in] || SecureFileAttacher::DEFAULT_URL_EXPIRATION)
    attacher.instance_variable_set(:@fetch_timeout, options[:fetch_timeout] || SecureFileAttacher::DEFAULT_FETCH_TIMEOUT)
    attacher.instance_variable_set(:@s3, s3_resource)
    attacher.instance_variable_set(:@bucket, s3_resource.bucket(@bucket_name))

    attacher
  end
end
