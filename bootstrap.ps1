# SmartSuite MCP Server - Bootstrap Installation Script (Windows)
# This script enables one-liner installation:
# irm https://raw.githubusercontent.com/Grupo-AFAL/smartsuite_mcp_server/main/bootstrap.ps1 | iex

$ErrorActionPreference = "Stop"

# Color output functions
function Print-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
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

# Determine installation directory
$InstallDir = Join-Path $env:USERPROFILE ".smartsuite_mcp"

Clear-Host

Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║                                                            ║"
Write-Host "║   SmartSuite MCP Server - One-Liner Installation          ║"
Write-Host "║                                                            ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

Print-Info "This script will install the SmartSuite MCP server to:"
Write-Host "  $InstallDir"
Write-Host ""

# Check for git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Print-Error "Git is not installed."
    Write-Host ""
    Print-Info "Please install Git for Windows from:"
    Write-Host "  https://git-scm.com/download/win"
    Write-Host ""
    exit 1
}

Print-Success "Git is installed"

# Clone or update repository
Print-Header "Downloading SmartSuite MCP Server"

try {
    if (Test-Path $InstallDir) {
        Print-Info "Existing installation found. Updating..."
        Set-Location $InstallDir
        git pull origin main
        Print-Success "Repository updated"
    } else {
        Print-Info "Cloning repository..."
        git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git $InstallDir
        Print-Success "Repository cloned"
    }

    # Run the main installation script
    Print-Header "Running Installation Script"

    Set-Location $InstallDir
    & .\install.ps1

    Write-Host ""
    Print-Success "Installation complete!"
    Print-Info "The SmartSuite MCP server has been installed to: $InstallDir"
}
catch {
    Print-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}
