#!/bin/bash

# SmartSuite MCP Server - Bootstrap Installation Script
# This script enables one-liner installation:
# curl -fsSL https://raw.githubusercontent.com/Grupo-AFAL/smartsuite_mcp_server/main/bootstrap.sh | bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Determine installation directory
INSTALL_DIR="$HOME/.smartsuite_mcp"

clear

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║   SmartSuite MCP Server - One-Liner Installation          ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

print_info "This script will install the SmartSuite MCP server to:"
echo "  $INSTALL_DIR"
echo ""

# Check for git
if ! command -v git &> /dev/null; then
    print_error "Git is not installed."
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        print_info "Install git with: xcode-select --install"
    elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
        print_info "Install git with your package manager:"
        echo "  Ubuntu/Debian: sudo apt-get install git"
        echo "  Fedora/RHEL: sudo dnf install git"
    fi
    exit 1
fi

print_success "Git is installed"

# Clone or update repository
print_header "Downloading SmartSuite MCP Server"

if [[ -d "$INSTALL_DIR" ]]; then
    print_info "Existing installation found. Updating..."
    cd "$INSTALL_DIR"
    git pull origin main
    print_success "Repository updated"
else
    print_info "Cloning repository..."
    git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git "$INSTALL_DIR"
    print_success "Repository cloned"
fi

# Run the main installation script
print_header "Running Installation Script"

cd "$INSTALL_DIR"
chmod +x install.sh
./install.sh

echo ""
print_success "Installation complete!"
print_info "The SmartSuite MCP server has been installed to: $INSTALL_DIR"
