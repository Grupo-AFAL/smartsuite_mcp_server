# Secure File Attachment Guide

Complete guide for securely attaching local files to SmartSuite records without exposing them publicly.

## Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [AWS S3 Setup](#aws-s3-setup)
- [Usage Examples](#usage-examples)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Alternative Solutions](#alternative-solutions)

---

## Overview

SmartSuite's `attach_file` API requires publicly accessible URLs to download files. This creates security risks when attaching sensitive documents. The `SecureFileAttacher` helper solves this by using AWS S3 with short-lived pre-signed URLs.

**Key Features:**
- ✅ Files never publicly accessible
- ✅ URLs expire in 60-120 seconds
- ✅ Automatic cleanup after SmartSuite fetches files
- ✅ Server-side encryption enabled
- ✅ Failsafe cleanup via S3 lifecycle policies

---

## The Problem

The SmartSuite API's `attach_file` endpoint requires URLs that are publicly accessible:

```ruby
# ❌ INSECURE: File must be publicly accessible
client.attach_file(
  'tbl_123',
  'rec_456',
  'attachments',
  ['https://example.com/sensitive_document.pdf']  # Anyone can access this!
)
```

**Security Risks:**
- Files exposed to internet during upload
- URLs could be intercepted or leaked
- No expiration on public URLs
- Compliance violations (HIPAA, GDPR, etc.)

---

## The Solution

`SecureFileAttacher` uses AWS S3 pre-signed URLs with minimal exposure:

```ruby
# ✅ SECURE: Temporary URLs with automatic cleanup
attacher = SecureFileAttacher.new(client, 'my-temp-bucket')
attacher.attach_file_securely(
  'tbl_123',
  'rec_456',
  'attachments',
  './sensitive_document.pdf'
)
```

**How It Works:**
1. Upload file to S3 with server-side encryption
2. Generate pre-signed URL (expires in 2 minutes)
3. SmartSuite fetches file from temporary URL
4. Delete file from S3 immediately after
5. S3 lifecycle policy provides failsafe cleanup

**Security Timeline:**
```
0:00 - File uploaded to S3 (encrypted)
0:01 - Pre-signed URL generated (expires 0:03)
0:02 - SmartSuite fetches file
0:03 - File deleted from S3
0:04 - URL expires (unusable)
```

---

## Prerequisites

### 1. AWS Account and S3 Bucket

Create an S3 bucket for temporary uploads:

```bash
# Create bucket (replace with your bucket name)
aws s3api create-bucket \
  --bucket my-smartsuite-temp-uploads \
  --region us-east-1

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket my-smartsuite-temp-uploads \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 2. AWS Credentials

Configure AWS credentials using one of these methods:

**Option A: Environment Variables** (Recommended for development)
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1
```

**Option B: Credentials File** (Recommended for personal use)
```bash
# ~/.aws/credentials
[default]
aws_access_key_id = your_access_key
aws_secret_access_key = your_secret_key

# ~/.aws/config
[default]
region = us-east-1
```

**Option C: IAM Instance Profile** (Recommended for EC2/ECS)
- Automatically provided when running on AWS infrastructure
- No credentials needed in code

### 3. Install AWS SDK

```bash
gem install aws-sdk-s3
```

Or add to Gemfile:
```ruby
gem 'aws-sdk-s3', '~> 1.0'
```

### 4. IAM Permissions

Create an IAM user/role with minimal permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::my-smartsuite-temp-uploads/temp-uploads/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::my-smartsuite-temp-uploads"
    }
  ]
}
```

---

## Quick Start

### Basic Usage

```ruby
require_relative 'lib/smartsuite_client'
require_relative 'lib/secure_file_attacher'

# Initialize clients
client = SmartSuiteClient.new(
  ENV['SMARTSUITE_API_KEY'],
  ENV['SMARTSUITE_ACCOUNT_ID']
)

attacher = SecureFileAttacher.new(client, 'my-temp-bucket')

# Attach a single file
attacher.attach_file_securely(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'attachments',
  './invoice.pdf'
)

# Attach multiple files
attacher.attach_file_securely(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'images',
  ['./photo1.jpg', './photo2.jpg', './photo3.png']
)
```

---

## AWS S3 Setup

### Step 1: Create S3 Bucket

```bash
aws s3api create-bucket \
  --bucket my-smartsuite-temp-uploads \
  --region us-east-1
```

### Step 2: Enable Encryption

```bash
aws s3api put-bucket-encryption \
  --bucket my-smartsuite-temp-uploads \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### Step 3: Configure CORS (Optional)

If SmartSuite needs CORS access:

```bash
aws s3api put-bucket-cors \
  --bucket my-smartsuite-temp-uploads \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedOrigins": ["https://app.smartsuite.com"],
      "AllowedMethods": ["GET"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3000
    }]
  }'
```

### Step 4: Set Up Lifecycle Policy

Automatically delete files after 1 day (failsafe):

```ruby
require_relative 'lib/smartsuite_client'
require_relative 'lib/secure_file_attacher'

client = SmartSuiteClient.new(ENV['SMARTSUITE_API_KEY'], ENV['SMARTSUITE_ACCOUNT_ID'])
attacher = SecureFileAttacher.new(client, 'my-temp-bucket')

# Generate lifecycle policy
lifecycle_policy = attacher.generate_lifecycle_policy

# Save to file
File.write('lifecycle.json', JSON.pretty_generate(lifecycle_policy))

# Apply via AWS CLI
# aws s3api put-bucket-lifecycle-configuration \
#   --bucket my-temp-bucket \
#   --lifecycle-configuration file://lifecycle.json
```

Or apply directly via CLI:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-smartsuite-temp-uploads \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "Delete temporary uploads after 1 day",
      "Status": "Enabled",
      "Prefix": "temp-uploads/",
      "Expiration": {
        "Days": 1
      }
    }]
  }'
```

---

## Usage Examples

### Example 1: Attach Single File

```ruby
attacher = SecureFileAttacher.new(client, 'my-temp-bucket')

result = attacher.attach_file_securely(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'attachments',
  './invoice.pdf'
)

puts "Attached: #{result['attachments'].length} files"
```

### Example 2: Attach Multiple Files

```ruby
result = attacher.attach_file_securely(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'documents',
  [
    './contract.pdf',
    './invoice.pdf',
    './receipt.pdf'
  ]
)
```

### Example 3: Custom Expiration (More Secure)

```ruby
# Ultra-short expiration for maximum security
attacher = SecureFileAttacher.new(
  client,
  'my-temp-bucket',
  url_expires_in: 60  # 1 minute only
)

attacher.attach_file_securely(
  'tbl_6796989a7ee3c6b731717836',
  'rec_68e3d5fb98c0282a4f1e2614',
  'sensitive_docs',
  './confidential.pdf'
)
```

### Example 4: Different AWS Region

```ruby
attacher = SecureFileAttacher.new(
  client,
  'my-eu-bucket',
  region: 'eu-west-1'
)
```

### Example 5: With Debug Logging

```ruby
ENV['SECURE_FILE_ATTACHER_DEBUG'] = 'true'

attacher = SecureFileAttacher.new(client, 'my-temp-bucket')
attacher.attach_file_securely('tbl_123', 'rec_456', 'files', './test.pdf')

# Output:
# [SecureFileAttacher] Uploading file to S3: ./test.pdf -> s3://my-bucket/temp-uploads/...
# [SecureFileAttacher] Generated pre-signed URL (expires in 120s)
# [SecureFileAttacher] Attaching 1 file(s) to SmartSuite record rec_456
# [SecureFileAttacher] SmartSuite attach successful, waiting for fetch...
# [SecureFileAttacher] Waited 30.0s for SmartSuite to fetch files
# [SecureFileAttacher] Deleted temporary file: s3://my-bucket/temp-uploads/...
```

### Example 6: Error Handling

```ruby
begin
  attacher.attach_file_securely(
    'tbl_123',
    'rec_456',
    'attachments',
    './document.pdf'
  )
rescue Errno::ENOENT => e
  puts "File not found: #{e.message}"
rescue ArgumentError => e
  puts "Invalid parameter: #{e.message}"
rescue Aws::S3::Errors::ServiceError => e
  puts "S3 error: #{e.message}"
rescue RuntimeError => e
  puts "SmartSuite API error: #{e.message}"
end
```

---

## Security Best Practices

### 1. Use Short Expiration Times

```ruby
# ✅ GOOD: 60-120 seconds
attacher = SecureFileAttacher.new(client, bucket, url_expires_in: 60)

# ❌ BAD: Too long
attacher = SecureFileAttacher.new(client, bucket, url_expires_in: 3600)
```

### 2. Separate Bucket for Temp Files

```ruby
# ✅ GOOD: Dedicated temp bucket
attacher = SecureFileAttacher.new(client, 'temp-uploads-bucket')

# ❌ BAD: Mixed with permanent files
attacher = SecureFileAttacher.new(client, 'all-files-bucket')
```

### 3. Minimal IAM Permissions

Only grant permissions needed for temp-uploads/ prefix:

```json
{
  "Resource": "arn:aws:s3:::my-bucket/temp-uploads/*"
}
```

### 4. Enable Encryption

Always enabled by `SecureFileAttacher`:
```ruby
obj.upload_file(path, server_side_encryption: 'AES256')
```

### 5. Monitor Access Logs

Enable S3 access logging:

```bash
aws s3api put-bucket-logging \
  --bucket my-smartsuite-temp-uploads \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "my-logs-bucket",
      "TargetPrefix": "smartsuite-temp-uploads/"
    }
  }'
```

### 6. Set Up Lifecycle Policy

Failsafe cleanup in case manual deletion fails:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-smartsuite-temp-uploads \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "Delete after 1 day",
      "Status": "Enabled",
      "Prefix": "temp-uploads/",
      "Expiration": {"Days": 1}
    }]
  }'
```

---

## Troubleshooting

### Error: "S3 bucket is not accessible"

**Cause:** AWS credentials not configured or bucket doesn't exist

**Solution:**
```bash
# Verify credentials
aws sts get-caller-identity

# Verify bucket exists
aws s3 ls s3://my-bucket
```

### Error: "File not found"

**Cause:** Invalid file path

**Solution:**
```ruby
# Use absolute paths or verify relative paths
file_path = File.expand_path('./invoice.pdf')
attacher.attach_file_securely('tbl_123', 'rec_456', 'files', file_path)
```

### Error: "MissingCredentialsError"

**Cause:** AWS credentials not configured

**Solution:**
```bash
# Set environment variables
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_REGION=us-east-1

# Or configure via AWS CLI
aws configure
```

### Files Not Being Deleted

**Cause:** Cleanup failed (network issue, permissions)

**Solution:** S3 lifecycle policy will delete after 1 day automatically

### SmartSuite Can't Fetch Files

**Cause:** URLs expired before SmartSuite fetched them

**Solution:** Increase expiration time:
```ruby
attacher = SecureFileAttacher.new(client, bucket, url_expires_in: 300)
```

---

## Alternative Solutions

If AWS S3 is not an option, consider:

### 1. Google Cloud Storage

Similar to S3 with signed URLs:
```ruby
require 'google/cloud/storage'

storage = Google::Cloud::Storage.new
bucket = storage.bucket('my-temp-bucket')
file = bucket.create_file(local_path, "temp/#{SecureRandom.uuid}/file.pdf")
signed_url = file.signed_url(method: 'GET', expires: 300)
```

### 2. Azure Blob Storage

Azure SAS tokens:
```ruby
require 'azure/storage/blob'

client = Azure::Storage::Blob::BlobService.create
container = 'temp-uploads'
blob_name = "#{SecureRandom.uuid}/file.pdf"
client.create_block_blob(container, blob_name, IO.read(local_path))
sas_token = client.generate_blob_sas_token(container, blob_name, expire_at: 5.minutes.from_now)
```

### 3. Self-Hosted Proxy Service

Deploy a temporary upload proxy (see main README for implementation).

---

## Cost Estimation

AWS S3 costs for typical usage:

**Assumptions:**
- 100 file uploads per day
- Average file size: 1 MB
- Files deleted after 30 seconds

**Monthly Costs:**
- Storage: $0.02 (100 MB stored for <1 hour each)
- PUT requests: $0.005 (3,000 requests)
- GET requests: $0.0004 (100 requests from SmartSuite)
- DELETE requests: Free
- **Total: ~$0.03/month**

Extremely cost-effective for the security benefits provided.

---

## Next Steps

1. ✅ [Set up AWS S3 bucket](#aws-s3-setup)
2. ✅ [Configure AWS credentials](#prerequisites)
3. ✅ [Install aws-sdk-s3 gem](#prerequisites)
4. ✅ [Try the basic example](#quick-start)
5. ✅ [Review security best practices](#security-best-practices)
6. ✅ [Set up lifecycle policy](#aws-s3-setup)

For complete examples, see `examples/secure_file_attachment.rb`.
