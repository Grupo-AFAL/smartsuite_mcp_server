# SmartSuite MCP Server - Windows Installation Script
# This script helps users set up the SmartSuite MCP server for Claude Desktop
# on Windows without requiring coding knowledge.

# Ensure script stops on errors
$ErrorActionPreference = "Stop"

# Function to print colored messages
function Print-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

function Print-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host $Message -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White
    Write-Host ""
}

# Check for Ruby installation
function Check-Ruby {
    Print-Header "Checking Ruby Installation"

    if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
        Print-Error "Ruby is not installed."
        Print-Info "Please install Ruby from: https://rubyinstaller.org/"
        Print-Info "Recommended: Ruby+Devkit 3.0 or higher"
        exit 1
    }

    $rubyVersion = (ruby -v | Select-String -Pattern '\d+\.\d+').Matches.Value
    $requiredVersion = [version]"3.0"
    $currentVersion = [version]$rubyVersion

    if ($currentVersion -lt $requiredVersion) {
        Print-Error "Ruby version $rubyVersion is installed, but version 3.0 or higher is required."
        Print-Info "Please upgrade Ruby from: https://rubyinstaller.org/"
        exit 1
    }

    Print-Success "Ruby $rubyVersion is installed"
}

# Install dependencies
function Install-Dependencies {
    Print-Header "Installing Dependencies"

    # Install bundler if not present
    if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
        Print-Info "Installing Bundler..."
        gem install bundler
    }

    Print-Info "Installing gem dependencies..."
    bundle install

    Print-Success "All dependencies installed"
}

# Get SmartSuite credentials
function Get-Credentials {
    Print-Header "SmartSuite API Credentials"

    Write-Host "To use this MCP server, you need SmartSuite API credentials."
    Write-Host ""
    Print-Info "You can find your credentials at:"
    Write-Host "  https://app.smartsuite.com/settings/api"
    Write-Host ""

    # Prompt for API key
    do {
        $apiKey = Read-Host "Enter your SmartSuite API Key"
    } while ([string]::IsNullOrWhiteSpace($apiKey))

    # Prompt for Account ID
    do {
        $accountId = Read-Host "Enter your SmartSuite Account ID"
    } while ([string]::IsNullOrWhiteSpace($accountId))

    Print-Success "Credentials configured"

    return @{
        ApiKey = $apiKey
        AccountId = $accountId
    }
}

# Configure Claude Desktop
function Configure-ClaudeDesktop {
    param(
        [string]$ApiKey,
        [string]$AccountId
    )

    Print-Header "Configuring Claude Desktop"

    $claudeConfigDir = Join-Path $env:APPDATA "Claude"
    $claudeConfigFile = Join-Path $claudeConfigDir "claude_desktop_config.json"
    $scriptDir = $PSScriptRoot

    # Create config directory if it doesn't exist
    if (-not (Test-Path $claudeConfigDir)) {
        Print-Info "Creating Claude Desktop config directory..."
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    }

    # Backup existing config if present
    if (Test-Path $claudeConfigFile) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = "${claudeConfigFile}.backup.$timestamp"
        Print-Info "Backing up existing configuration to: $backupFile"
        Copy-Item $claudeConfigFile $backupFile

        # Read existing config
        $existingConfig = Get-Content $claudeConfigFile -Raw | ConvertFrom-Json
    } else {
        $existingConfig = @{}
    }

    # Create/update MCP server configuration
    Print-Info "Adding SmartSuite MCP server to Claude Desktop configuration..."

    # Ensure mcpServers object exists
    if (-not $existingConfig.mcpServers) {
        $existingConfig | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{} -Force
    }

    # Add SmartSuite server configuration
    $smartsuiteConfig = @{
        command = "ruby"
        args = @("$scriptDir\smartsuite_server.rb")
        env = @{
            SMARTSUITE_API_KEY = $ApiKey
            SMARTSUITE_ACCOUNT_ID = $AccountId
        }
    }

    $existingConfig.mcpServers | Add-Member -MemberType NoteProperty -Name "smartsuite" -Value $smartsuiteConfig -Force

    # Write updated config
    $existingConfig | ConvertTo-Json -Depth 10 | Set-Content $claudeConfigFile

    Print-Success "Claude Desktop configured"
    Print-Info "Configuration file: $claudeConfigFile"
}

# Final instructions
function Print-FinalInstructions {
    param([string]$ConfigFile)

    Print-Header "Installation Complete! 🎉"

    Write-Host "The SmartSuite MCP server has been successfully installed and configured."
    Write-Host ""
    Print-Info "Next steps:"
    Write-Host "  1. Restart Claude Desktop to load the new MCP server"
    Write-Host "  2. In Claude Desktop, you should see SmartSuite tools available"
    Write-Host "  3. Try asking Claude: 'List my SmartSuite solutions'"
    Write-Host ""
    Print-Info "Configuration location:"
    Write-Host "  $ConfigFile"
    Write-Host ""
    Print-Info "For troubleshooting, see:"
    Write-Host "  docs\getting-started\troubleshooting.md"
    Write-Host ""
    Print-Success "Enjoy using SmartSuite with Claude! 🚀"
}

# Main installation flow
function Main {
    Clear-Host

    Write-Host "╔════════════════════════════════════════════════════════════╗"
    Write-Host "║                                                            ║"
    Write-Host "║        SmartSuite MCP Server Installation Script          ║"
    Write-Host "║                     (Windows)                              ║"
    Write-Host "║                                                            ║"
    Write-Host "║  This script will help you set up the SmartSuite MCP      ║"
    Write-Host "║  server for use with Claude Desktop.                      ║"
    Write-Host "║                                                            ║"
    Write-Host "╚════════════════════════════════════════════════════════════╝"
    Write-Host ""

    Print-Info "Press Enter to begin installation, or Ctrl+C to cancel"
    Read-Host

    try {
        # Run installation steps
        Check-Ruby
        Install-Dependencies
        $credentials = Get-Credentials
        Configure-ClaudeDesktop -ApiKey $credentials.ApiKey -AccountId $credentials.AccountId
        Print-FinalInstructions -ConfigFile (Join-Path $env:APPDATA "Claude\claude_desktop_config.json")
    }
    catch {
        Print-Error "Installation failed: $($_.Exception.Message)"
        exit 1
    }
}

# Run main function
Main
