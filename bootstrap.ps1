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

# Exit with pause so user can read error messages (needed for irm | iex)
function Exit-WithPause {
    param([int]$ExitCode = 1)
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $ExitCode
}

# Check for WinGet
function Test-WinGet {
    return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null
}

# Install Git using WinGet
function Install-Git {
    Print-Header "Installing Git"

    if (Test-WinGet) {
        Print-Info "Installing Git using Windows Package Manager (WinGet)..."
        Print-Info "This may take a few minutes..."

        winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements

        # Refresh environment variables to pick up Git
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

        if (Get-Command git -ErrorAction SilentlyContinue) {
            Print-Success "Git installed successfully"
            return $true
        } else {
            Print-Error "Git installation completed but git command not found."
            Print-Info "Please restart PowerShell and run this script again."
            return $false
        }
    } else {
        Print-Error "Windows Package Manager (WinGet) is not available."
        Print-Info "WinGet is built into Windows 10 (1809+) and Windows 11."
        return $false
    }
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
    Print-Warning "Git is not installed."
    Write-Host ""

    $response = Read-Host "Would you like to install Git automatically? (yes/no)"
    if ($response -eq "yes" -or $response -eq "y") {
        $installed = Install-Git
        if (-not $installed) {
            Print-Info "Please install Git manually from:"
            Write-Host "  https://git-scm.com/download/win"
            Write-Host ""
            Exit-WithPause
        }
    } else {
        Print-Info "Please install Git for Windows from:"
        Write-Host "  https://git-scm.com/download/win"
        Write-Host ""
        Print-Info "After installing Git, run this script again."
        Exit-WithPause
    }
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
    Exit-WithPause
}
