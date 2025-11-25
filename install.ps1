# SmartSuite MCP Server - Windows Installation Script
# This script helps users set up the SmartSuite MCP server for Claude Desktop
# on Windows without requiring coding knowledge.

# Ensure script stops on errors
$ErrorActionPreference = "Stop"

# Function to print colored messages
function Print-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Print-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Host $Message -ForegroundColor White
    Write-Host "========================================" -ForegroundColor White
    Write-Host ""
}

# Check for WinGet (Windows Package Manager)
function Test-WinGet {
    return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
}

# Install Ruby using WinGet
function Install-Ruby {
    Print-Header "Installing Ruby"

    if (Test-WinGet) {
        Print-Info "Installing Ruby using Windows Package Manager (WinGet)..."
        Print-Info "This may take a few minutes..."

        # Try to install Ruby+Devkit (try latest version first, then older versions)
        $installed = $false

        # Try Ruby 3.4 with DevKit first (latest stable)
        Print-Info "Trying RubyInstallerTeam.RubyWithDevKit.3.4..."
        winget install --id RubyInstallerTeam.RubyWithDevKit.3.4 --silent --accept-package-agreements --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0) {
            $installed = $true
        } else {
            # Try Ruby 3.3 with DevKit
            Print-Info "Trying RubyInstallerTeam.RubyWithDevKit.3.3..."
            winget install --id RubyInstallerTeam.RubyWithDevKit.3.3 --silent --accept-package-agreements --accept-source-agreements 2>$null
            if ($LASTEXITCODE -eq 0) {
                $installed = $true
            } else {
                # Try Ruby 3.2 with DevKit
                Print-Info "Trying RubyInstallerTeam.RubyWithDevKit.3.2..."
                winget install --id RubyInstallerTeam.RubyWithDevKit.3.2 --silent --accept-package-agreements --accept-source-agreements 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $installed = $true
                } else {
                    # Try generic Ruby with DevKit
                    Print-Info "Trying RubyInstallerTeam.RubyWithDevKit..."
                    winget install --id RubyInstallerTeam.RubyWithDevKit --silent --accept-package-agreements --accept-source-agreements 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $installed = $true
                    }
                }
            }
        }

        if (-not $installed) {
            Print-Error "WinGet could not find a Ruby package."
            Print-Info "Please install Ruby manually from: https://rubyinstaller.org/"
            Print-Info "Recommended: Ruby+Devkit 3.0 or higher"
            exit 1
        }

        # Refresh environment variables to pick up Ruby
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        Print-Success "Ruby installed successfully"
    } else {
        Print-Error "Windows Package Manager (WinGet) is not available."
        Print-Info "WinGet is built into Windows 10 (1809+) and Windows 11."
        Print-Info ""
        Print-Info "Please install Ruby manually from: https://rubyinstaller.org/"
        Print-Info "Recommended: Ruby+Devkit 3.0 or higher"
        Print-Info ""
        Print-Info "After installing Ruby, run this script again."
        exit 1
    }
}

# Check for Ruby installation
function Check-Ruby {
    Print-Header "Checking Ruby Installation"

    $needsInstall = $false
    $rubyVersion = $null

    # Check if Ruby is installed
    if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
        Print-Warning "Ruby is not installed."
        $needsInstall = $true
    } else {
        # Ruby exists, check version
        $rubyVersion = (ruby -v | Select-String -Pattern '\d+\.\d+').Matches.Value
        $requiredVersion = [version]"3.0"
        $currentVersion = [version]$rubyVersion

        if ($currentVersion -lt $requiredVersion) {
            Print-Warning "Ruby version $rubyVersion is installed, but version 3.0 or higher is required."
            $needsInstall = $true
        }
    }

    # Offer to install Ruby if needed
    if ($needsInstall) {
        $response = Read-Host "Would you like to install Ruby automatically? (yes/no)"
        if ($response -eq "yes" -or $response -eq "y") {
            Install-Ruby

            # Verify installation succeeded
            if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
                Print-Error "Ruby installation failed. Please install manually from: https://rubyinstaller.org/"
                exit 1
            }

            $rubyVersion = (ruby -v | Select-String -Pattern '\d+\.\d+').Matches.Value
            $requiredVersion = [version]"3.0"
            $currentVersion = [version]$rubyVersion

            if ($currentVersion -lt $requiredVersion) {
                Print-Error "Ruby version $rubyVersion was installed, but version 3.0 or higher is required."
                Print-Info "Please install Ruby manually from: https://rubyinstaller.org/"
                exit 1
            }
        } else {
            Print-Info "Please install Ruby from: https://rubyinstaller.org/"
            Print-Info "Recommended: Ruby+Devkit 3.0 or higher"
            Print-Info "After installing Ruby, run this script again."
            exit 1
        }
    }

    Print-Success "Ruby $rubyVersion is installed"
}

# Install dependencies
function Install-Dependencies {
    Print-Header "Installing Dependencies"

    # Initialize MSYS2 build tools (required for native gem extensions like sqlite3)
    Print-Info "Initializing MSYS2 build environment..."
    if (Get-Command ridk -ErrorAction SilentlyContinue) {
        # Run ridk install to ensure MSYS2 is set up (option 1 = base installation)
        # This is needed for compiling native extensions
        ridk enable 2>$null
        Print-Success "MSYS2 build environment ready"
    } else {
        Print-Warning "ridk not found - native gem compilation may fail"
        Print-Info "If gem installation fails, run: ridk install"
    }

    # Install bundler if not present
    if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
        Print-Info "Installing Bundler..."
        gem install bundler
    }

    # Pre-install sqlite3 with platform=ruby to ensure native compilation
    # The pre-built Windows binaries often have compatibility issues
    Print-Info "Installing sqlite3 gem (this may take a few minutes)..."
    gem install sqlite3 --platform=ruby 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "sqlite3 native build failed, trying pre-built binary..."
        gem install sqlite3
    }

    Print-Info "Installing remaining gem dependencies..."
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

# Get the full path to the Ruby executable
function Get-RubyPath {
    # First try to get Ruby from PATH
    $rubyCommand = Get-Command ruby -ErrorAction SilentlyContinue
    if ($rubyCommand) {
        return $rubyCommand.Source
    }

    # Common Ruby installation paths on Windows
    $commonPaths = @(
        "C:\Ruby34-x64\bin\ruby.exe",
        "C:\Ruby33-x64\bin\ruby.exe",
        "C:\Ruby32-x64\bin\ruby.exe",
        "C:\Ruby31-x64\bin\ruby.exe",
        "C:\Ruby30-x64\bin\ruby.exe",
        "C:\Ruby34\bin\ruby.exe",
        "C:\Ruby33\bin\ruby.exe",
        "C:\Ruby32\bin\ruby.exe",
        "C:\Ruby31\bin\ruby.exe",
        "C:\Ruby30\bin\ruby.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Fallback to just "ruby" and hope it's in PATH when Claude Desktop runs
    return "ruby"
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

    # Get the full path to Ruby
    $rubyPath = Get-RubyPath
    Print-Info "Using Ruby at: $rubyPath"

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
    }

    # Create/update MCP server configuration
    Print-Info "Adding SmartSuite MCP server to Claude Desktop configuration..."

    # Build the SmartSuite server configuration
    $smartsuiteConfig = @{
        command = $rubyPath
        args = @("$scriptDir\smartsuite_server.rb")
        env = @{
            SMARTSUITE_API_KEY = $ApiKey
            SMARTSUITE_ACCOUNT_ID = $AccountId
        }
    }

    # Build the complete config object
    $config = @{
        mcpServers = @{
            smartsuite = $smartsuiteConfig
        }
    }

    # Write config as JSON
    $config | ConvertTo-Json -Depth 10 | Set-Content $claudeConfigFile -Encoding UTF8

    Print-Success "Claude Desktop configured"
    Print-Info "Configuration file: $claudeConfigFile"
}

# Final instructions
function Print-FinalInstructions {
    param([string]$ConfigFile)

    Print-Header "Installation Complete!"

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
    Print-Success "Enjoy using SmartSuite with Claude!"
}

# Main installation flow
function Main {
    Clear-Host

    Write-Host "+------------------------------------------------------------+"
    Write-Host "|                                                            |"
    Write-Host "|        SmartSuite MCP Server Installation Script           |"
    Write-Host "|                     (Windows)                              |"
    Write-Host "|                                                            |"
    Write-Host "|  This script will help you set up the SmartSuite MCP      |"
    Write-Host "|  server for use with Claude Desktop.                       |"
    Write-Host "|                                                            |"
    Write-Host "+------------------------------------------------------------+"
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
