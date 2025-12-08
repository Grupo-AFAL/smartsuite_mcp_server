# Kamal Deployment Guide

This guide covers deploying the SmartSuite MCP Server to AWS EC2 using Kamal.

## Prerequisites

### Local Machine
- Docker Desktop installed and running
- Ruby 3.4.7+ with Bundler
- Git

### AWS Account
- IAM user with programmatic access (not root account)
- EC2, S3, and IAM permissions

## Step 1: AWS Setup

### Create IAM Admin User

1. Go to AWS Console → IAM → Users → Create User
2. Name: `smartsuite-mcp-admin`
3. Enable "Provide user access to the AWS Management Console"
4. Attach policy: `AdministratorAccess` (or create custom policy with EC2, S3, IAM)
5. Enable MFA for security
6. Save credentials securely

### Create EC2 Instance

1. **AMI**: Ubuntu 24.04 LTS
2. **Instance Type**: `t3.small` (2 vCPU, 2GB RAM) - recommended minimum
3. **Key Pair**: Create new → `smartsuite-mcp-key` → Download `.pem` file
4. **Security Group**:
   - SSH (22) from your IP
   - HTTP (80) from anywhere
   - HTTPS (443) from anywhere
5. **Storage**: 20GB gp3 (enable encryption)
6. **Elastic IP**: Allocate and associate with instance

```bash
# Move key to SSH directory
mv ~/Downloads/smartsuite-mcp-key.pem ~/.ssh/
chmod 400 ~/.ssh/smartsuite-mcp-key.pem

# Test SSH connection
ssh -i ~/.ssh/smartsuite-mcp-key.pem ubuntu@<YOUR_ELASTIC_IP>
```

### Prepare EC2 Instance

SSH into your instance and install Docker:

```bash
# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu

# IMPORTANT: Reboot for group changes to take effect
sudo reboot
```

Wait 1-2 minutes, then SSH back in and verify:

```bash
docker ps  # Should work without sudo
```

### Create GitHub Container Registry Token

1. Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
2. Generate new token with `write:packages` and `read:packages` scopes
3. Save the token securely

## Step 2: Local Configuration

### Environment Variables

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Kamal deployment variables
export KAMAL_REGISTRY_USERNAME=<your_github_username>
export DEPLOY_SERVER_IP=<your_elastic_ip>
export DEPLOY_HOST=<your_domain_or_ip.nip.io>
```

Reload: `source ~/.zshrc`

### Create .env File

Create `.env` in the project root (this file is gitignored):

```bash
# GitHub Container Registry
KAMAL_REGISTRY_PASSWORD=ghp_xxxxxxxxxxxxxxxxxxxx

# Rails
RAILS_MASTER_KEY=<from config/master.key>

# PostgreSQL (use container hostname, NOT public IP)
DATABASE_URL=postgres://smartsuite_mcp:<password>@smartsuite-mcp-db:5432/smartsuite_mcp_production
POSTGRES_PASSWORD=<generate_secure_password>

# AWS S3 Backups (separate IAM user for isolation)
BACKUP_AWS_ACCESS_KEY_ID=<backup_iam_user_key>
BACKUP_AWS_SECRET_ACCESS_KEY=<backup_iam_user_secret>
BACKUP_AWS_REGION=us-east-2
BACKUP_S3_BUCKET=<your_backup_bucket>
```

Generate a secure password:
```bash
openssl rand -base64 32
```

### Create deploy.yml

Copy and customize the deployment config:

```bash
cp config/deploy.yml.example config/deploy.yml
```

Edit `config/deploy.yml`:
- Set `image:` to `<your_github_username>/smartsuite-mcp`
- Set `servers: web:` to your Elastic IP
- Set `proxy: host:` to your domain or `<ip>.nip.io`
- Set `registry: username:` to your GitHub username
- Set `accessories: db: host:` to your Elastic IP

## Step 3: Deploy

### Initial Setup

```bash
kamal setup
```

This will:
- Install Docker on the server (if needed)
- Pull and start kamal-proxy
- Start the PostgreSQL accessory
- Build and push your Docker image
- Start the Rails application

### Subsequent Deploys

```bash
kamal deploy
```

**Important**: Kamal builds from your git commit, not working directory. Always commit changes before deploying:

```bash
git add .
git commit -m "Your changes"
kamal deploy
```

## Step 4: Create Users and API Keys

Open the Rails console:

```bash
kamal console
```

Create a user and API key:

```ruby
user = User.create!(name: "Your Name", email: "you@example.com", smartsuite_api_key: "your_smartsuite_key", smartsuite_account_id: "your_account_id")
key = user.api_keys.create!
puts key.token
```

## Step 5: Test the API

```bash
curl -X POST "https://<your_domain>/mcp" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your_api_key>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## Step 6: Configure Backups

### Create Backup IAM User

1. Create IAM user: `smartsuite-mcp-backup`
2. Attach custom policy (replace bucket name):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-backup-bucket",
                "arn:aws:s3:::your-backup-bucket/*"
            ]
        }
    ]
}
```

3. Create access key and add to `.env` as `BACKUP_AWS_*` variables
4. Redeploy: `kamal deploy`

### Test Backup

```bash
kamal app exec --reuse "bin/backup-db"
```

### Schedule Automatic Backups

SSH into EC2 and add cron job:

```bash
crontab -e
```

Add (runs daily at 3 AM UTC):
```
0 3 * * * docker exec $(docker ps -q -f name=smartsuite-mcp-web) bin/backup-db >> /var/log/smartsuite-backup.log 2>&1
```

## Common Commands

```bash
# View logs
kamal app logs

# Open Rails console
kamal console

# Open shell in container
kamal shell

# Run database migrations
kamal app exec --reuse "bin/rails db:migrate"

# Check running containers
kamal app details

# Restart application
kamal app boot
```

## Troubleshooting

### Docker Permission Denied

```
permission denied while trying to connect to the Docker daemon socket
```

**Fix**: Add user to docker group and reboot EC2:
```bash
sudo usermod -aG docker ubuntu
sudo reboot
```

### Database Connection Timeout

```
connection to server at "18.x.x.x", port 5432 failed: Connection timed out
```

**Fix**: Use Docker container hostname in DATABASE_URL, not public IP:
```
DATABASE_URL=postgres://...@smartsuite-mcp-db:5432/...
```

### Environment Variables Not Updated

Kamal reads secrets at deploy time. After changing `.env`:
```bash
kamal deploy
```

### Build Not Picking Up Changes

Kamal builds from git commits, not working directory:
```bash
git add .
git commit -m "Your changes"
kamal deploy
```

### SSL Certificate Issues

If using a custom domain, ensure DNS is properly configured. For testing, use nip.io:
```yaml
proxy:
  host: <your_ip>.nip.io
```

## Security Best Practices

1. **Never use AWS root account** - Create IAM users with minimal permissions
2. **Enable MFA** on all IAM users
3. **Separate IAM users** for different functions (deployment, backups, attachments)
4. **Rotate credentials** regularly
5. **Use security groups** to restrict SSH access to your IP
6. **Enable EBS encryption** for data at rest
7. **Keep .env out of git** - It's gitignored by default

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         EC2 Instance                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │   kamal-proxy   │  │  Rails App      │  │  PostgreSQL │  │
│  │   (ports 80/443)│  │  (Docker)       │  │  (Docker)   │  │
│  │   SSL termination│  │                 │  │             │  │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘  │
│           │                    │                   │         │
│           └────────────────────┴───────────────────┘         │
│                         Docker Network (kamal)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   S3 Bucket     │
                    │   (Backups)     │
                    └─────────────────┘
```
