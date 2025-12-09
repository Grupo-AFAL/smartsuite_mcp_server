# SmartSuite MCP Server - Installation Script for Windows
#
# Two installation modes:
#   LOCAL:  Run the MCP server locally (requires Ruby, SmartSuite credentials)
#   REMOTE: Connect to a hosted MCP server (requires Node.js, server API key)
#
# Usage:
#   Local:  .\install.ps1 local
#   Remote: .\install.ps1 remote <MCP_URL> <API_KEY>
#   Remote: iwr -useb https://your-server.com/install.ps1 | iex; Install-SmartSuiteMCP remote <URL> <KEY>

param(
    [Parameter(Position=0)]
    [ValidateSet("local", "remote")]
    [string]$Mode,

    [Parameter(Position=1)]
    [string]$McpUrl,

    [Parameter(Position=2)]
    [string]$ApiKey
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Step { param([string]$Message) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warning { param([string]$Message) Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Error { param([string]$Message) Write-Host "[X] " -ForegroundColor Red -NoNewline; Write-Host $Message }

function Show-Usage {
    Write-Host "SmartSuite MCP Server Installer" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\install.ps1 local                          Install local server (stdio mode)"
    Write-Host "  .\install.ps1 remote <MCP_URL> <API_KEY>     Connect to hosted server (HTTP mode)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\install.ps1 local"
    Write-Host "  .\install.ps1 remote https://smartsuite-mcp.example.com/mcp sk_live_abc123"
    Write-Host ""
    Write-Host "Modes:"
    Write-Host "  local  - Runs MCP server on your machine"
    Write-Host "           Requires: Ruby, SmartSuite API credentials"
    Write-Host "           Best for: Single user, full control, offline capability"
    Write-Host ""
    Write-Host "  remote - Connects to a hosted MCP server"
    Write-Host "           Requires: Node.js (for mcp-remote bridge)"
    Write-Host "           Best for: Teams, managed infrastructure, no local setup"
    Write-Host ""
}

# ============================================================================
# Node.js Installation (for remote mode)
# ============================================================================

function Test-NodeInstalled {
    try {
        $null = Get-Command npx -ErrorAction Stop
        $version = node -v 2>$null
        Write-Success "Node.js is installed ($version)"
        return $true
    } catch {
        return $false
    }
}

function Install-NodeJS {
    Write-Step "Node.js not found. Installing..."

    # Check if winget is available (Windows 10 1709+ and Windows 11)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Step "Installing Node.js via winget..."
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        if (Test-NodeInstalled) {
            return $true
        }
    }

    # Fallback: Download and install directly
    Write-Step "Installing Node.js via direct download..."
    $nodeVersion = "20.10.0"
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $installerUrl = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-$arch.msi"
    $installerPath = "$env:TEMP\nodejs-installer.msi"

    Write-Step "Downloading Node.js $nodeVersion..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Step "Running installer (may require admin privileges)..."
    Start-Process msiexec.exe -ArgumentList "/i", $installerPath, "/quiet", "/norestart" -Wait -Verb RunAs

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    if (Test-NodeInstalled) {
        return $true
    }

    Write-Error "Node.js installation failed"
    Write-Host ""
    Write-Host "Please install Node.js manually from: https://nodejs.org"
    return $false
}

# ============================================================================
# Ruby Installation (for local mode)
# ============================================================================

function Test-RubyInstalled {
    try {
        $null = Get-Command ruby -ErrorAction Stop
        $version = ruby -v 2>$null
        if ($version -match "ruby (\d+)\.(\d+)") {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 2)) {
                Write-Success "Ruby is installed ($version)"
                return $true
            } else {
                Write-Warning "Ruby found but version >= 3.2 required (found $version)"
                return $false
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Install-Ruby {
    Write-Step "Ruby >= 3.2 not found. Installing..."

    # Use RubyInstaller for Windows
    $rubyVersion = "3.3.0-1"
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $installerUrl = "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-$rubyVersion/rubyinstaller-devkit-$rubyVersion-$arch.exe"
    $installerPath = "$env:TEMP\rubyinstaller.exe"

    Write-Step "Downloading RubyInstaller $rubyVersion..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Step "Running installer (may require admin privileges)..."
    Start-Process $installerPath -ArgumentList "/verysilent", "/tasks=modpath" -Wait -Verb RunAs

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    if (Test-RubyInstalled) {
        return $true
    }

    Write-Error "Ruby installation failed"
    Write-Host ""
    Write-Host "Please install Ruby manually from: https://rubyinstaller.org"
    return $false
}

# ============================================================================
# Configuration Helpers
# ============================================================================

function Get-ClaudeConfigPath {
    return "$env:APPDATA\Claude\claude_desktop_config.json"
}

function Get-RemoteConfig {
    # Use cmd.exe wrapper to handle spaces in "Program Files" path
    # Pass --header and Authorization as separate args for proper parsing
    return @"
{
  "mcpServers": {
    "smartsuite": {
      "command": "cmd.exe",
      "args": ["/c", "npx", "-y", "mcp-remote", "$McpUrl", "--header", "Authorization: Bearer $ApiKey"]
    }
  }
}
"@
}

function Get-LocalConfig {
    param([string]$ServerPath)
    $escapedPath = $ServerPath -replace '\\', '/'
    return @"
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["$escapedPath/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "YOUR_SMARTSUITE_API_KEY",
        "SMARTSUITE_ACCOUNT_ID": "YOUR_SMARTSUITE_ACCOUNT_ID"
      }
    }
  }
}
"@
}

function Configure-ClaudeDesktop {
    param([string]$ConfigJson)

    $configPath = Get-ClaudeConfigPath
    $configDir = Split-Path $configPath -Parent

    Write-Host ""
    Write-Step "Configuring Claude Desktop"

    # Create directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if (Test-Path $configPath) {
        # File exists - merge smartsuite into existing config
        Write-Step "Existing config found, merging smartsuite server..."

        try {
            # PowerShell 5.1 compatible: ConvertFrom-Json returns PSCustomObject, not Hashtable
            $existingJson = Get-Content $configPath -Raw
            $existing = $existingJson | ConvertFrom-Json
            $newConfig = $ConfigJson | ConvertFrom-Json

            # Ensure mcpServers exists (PSCustomObject property access)
            if (-not (Get-Member -InputObject $existing -Name 'mcpServers' -MemberType Properties)) {
                $existing | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue (New-Object PSObject)
            }

            # Add/update smartsuite server
            $smartsuiteConfig = $newConfig.mcpServers.smartsuite
            if (Get-Member -InputObject $existing.mcpServers -Name 'smartsuite' -MemberType Properties) {
                $existing.mcpServers.smartsuite = $smartsuiteConfig
            } else {
                $existing.mcpServers | Add-Member -NotePropertyName 'smartsuite' -NotePropertyValue $smartsuiteConfig
            }

            # Write back with proper formatting (UTF8 without BOM)
            $jsonContent = $existing | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($configPath, $jsonContent)
            Write-Success "Config updated: $configPath"
        } catch {
            Write-Error "Failed to merge config: $_"
            Write-Host ""
            Write-Host "Please add this to your config manually:"
            Write-Host $ConfigJson -ForegroundColor Gray
        }
    } else {
        # File doesn't exist - create it (UTF8 without BOM)
        [System.IO.File]::WriteAllText($configPath, $ConfigJson)
        Write-Success "Config created: $configPath"
    }
}

# ============================================================================
# Installation Modes
# ============================================================================

function Install-Remote {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "    SmartSuite MCP Server - Remote Mode Installation" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Server URL: $McpUrl"
    Write-Host ""

    # Step 1: Ensure Node.js is installed
    if (-not (Test-NodeInstalled)) {
        if (-not (Install-NodeJS)) {
            exit 1
        }
    }

    # Step 2: Pre-cache mcp-remote
    Write-Step "Pre-caching mcp-remote package..."
    try {
        npx -y mcp-remote --version 2>$null | Out-Null
    } catch {
        # Ignore errors during pre-cache
    }
    Write-Success "mcp-remote ready"

    # Step 3: Configure Claude Desktop automatically
    Configure-ClaudeDesktop (Get-RemoteConfig)

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "                Installation Complete" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Restart Claude Desktop"
    Write-Host "  2. Look for 'smartsuite' in the MCP servers list"
    Write-Host "  3. Try: 'List my SmartSuite solutions'"
    Write-Host ""
}

function Install-Local {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "     SmartSuite MCP Server - Local Mode Installation" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Step 1: Ensure Ruby is installed
    if (-not (Test-RubyInstalled)) {
        if (-not (Install-Ruby)) {
            exit 1
        }
    }

    # Step 2: Clone or update repository
    $installDir = "$env:USERPROFILE\.smartsuite-mcp"

    if (Test-Path $installDir) {
        Write-Step "Updating existing installation..."
        Push-Location $installDir
        git pull origin main
        Pop-Location
    } else {
        Write-Step "Cloning SmartSuite MCP server..."
        git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git $installDir
    }

    # Step 3: Install dependencies
    Write-Step "Installing Ruby dependencies..."
    Push-Location $installDir
    bundle install
    Pop-Location

    Write-Success "Server installed at: $installDir"

    # Step 4: Configure Claude Desktop automatically
    Configure-ClaudeDesktop (Get-LocalConfig $installDir)

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "                Installation Complete" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT: Update the config with your SmartSuite credentials:" -ForegroundColor Yellow
    Write-Host "  - SMARTSUITE_API_KEY: From SmartSuite > Settings > API"
    Write-Host "  - SMARTSUITE_ACCOUNT_ID: From your SmartSuite URL"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Add your SmartSuite credentials to the config"
    Write-Host "  2. Restart Claude Desktop"
    Write-Host "  3. Look for 'smartsuite' in the MCP servers list"
    Write-Host "  4. Try: 'List my SmartSuite solutions'"
    Write-Host ""
}

# ============================================================================
# Main
# ============================================================================

if (-not $Mode) {
    Show-Usage
    exit 1
}

if ($Mode -eq "remote" -and (-not $McpUrl -or -not $ApiKey)) {
    Write-Error "Remote mode requires MCP_URL and API_KEY"
    Write-Host ""
    Show-Usage
    exit 1
}

switch ($Mode) {
    "local" { Install-Local }
    "remote" { Install-Remote }
}
