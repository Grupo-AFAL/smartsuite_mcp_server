#!/bin/bash
# SmartSuite MCP Server - Installation Script for macOS/Linux
#
# Two installation modes:
#   LOCAL:  Run the MCP server locally (requires Ruby, SmartSuite credentials)
#   REMOTE: Connect to a hosted MCP server (requires Node.js, server API key)
#
# Usage:
#   Local:  ./install.sh local
#   Remote: ./install.sh remote <MCP_URL> <API_KEY>
#   Remote: curl -fsSL https://your-server.com/install.sh | bash -s -- remote <URL> <KEY>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Parse arguments
MODE="${1:-}"
MCP_URL="${2:-}"
API_KEY="${3:-}"

show_usage() {
    echo "SmartSuite MCP Server Installer"
    echo ""
    echo "Usage:"
    echo "  $0 local                          Install local server (stdio mode)"
    echo "  $0 remote <MCP_URL> <API_KEY>     Connect to hosted server (HTTP mode)"
    echo ""
    echo "Examples:"
    echo "  $0 local"
    echo "  $0 remote https://smartsuite-mcp.example.com/mcp sk_live_abc123"
    echo ""
    echo "Modes:"
    echo "  local  - Runs MCP server on your machine"
    echo "           Requires: Ruby, SmartSuite API credentials"
    echo "           Best for: Single user, full control, offline capability"
    echo ""
    echo "  remote - Connects to a hosted MCP server"
    echo "           Requires: Node.js (for mcp-remote bridge)"
    echo "           Best for: Teams, managed infrastructure, no local setup"
    echo ""
}

if [ -z "$MODE" ]; then
    show_usage
    exit 1
fi

if [ "$MODE" == "remote" ] && ([ -z "$MCP_URL" ] || [ -z "$API_KEY" ]); then
    print_error "Remote mode requires MCP_URL and API_KEY"
    echo ""
    show_usage
    exit 1
fi

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)

# ============================================================================
# Node.js Installation (for remote mode)
# ============================================================================

check_node() {
    if command -v npx &> /dev/null; then
        NODE_VERSION=$(node -v 2>/dev/null || echo "unknown")
        print_success "Node.js is installed ($NODE_VERSION)"
        return 0
    fi
    return 1
}

install_node_fnm() {
    print_step "Installing fnm (Fast Node Manager)..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell

    # Source fnm for current session
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env --shell bash 2>/dev/null || true)"

    print_step "Installing Node.js LTS..."
    fnm install --lts
    fnm use lts-latest

    print_success "Node.js installed via fnm"
}

install_node_package_manager() {
    if [[ "$OS" == "linux" ]]; then
        if command -v apt-get &> /dev/null; then
            print_step "Installing Node.js via apt..."
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif command -v dnf &> /dev/null; then
            print_step "Installing Node.js via dnf..."
            sudo dnf install -y nodejs
        elif command -v yum &> /dev/null; then
            print_step "Installing Node.js via yum..."
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo yum install -y nodejs
        elif command -v pacman &> /dev/null; then
            print_step "Installing Node.js via pacman..."
            sudo pacman -S --noconfirm nodejs npm
        else
            return 1
        fi
        print_success "Node.js installed via package manager"
        return 0
    fi
    return 1
}

install_node() {
    print_step "Node.js not found. Installing..."

    # Try fnm first (works on both macOS and Linux, no sudo needed)
    if install_node_fnm; then
        return 0
    fi

    # Fallback to package manager on Linux
    if [[ "$OS" == "linux" ]] && install_node_package_manager; then
        return 0
    fi

    print_error "Could not automatically install Node.js"
    echo ""
    echo "Please install Node.js manually:"
    if [[ "$OS" == "macos" ]]; then
        echo "  Option 1: Download from https://nodejs.org"
        echo "  Option 2: brew install node"
    else
        echo "  Download from https://nodejs.org"
    fi
    exit 1
}

# ============================================================================
# Ruby Installation (for local mode)
# ============================================================================

check_ruby() {
    if command -v ruby &> /dev/null; then
        RUBY_VERSION=$(ruby -v 2>/dev/null | cut -d' ' -f2)
        # Check if version is >= 3.2
        if ruby -e 'exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2") ? 0 : 1)' 2>/dev/null; then
            print_success "Ruby is installed ($RUBY_VERSION)"
            return 0
        else
            print_warning "Ruby $RUBY_VERSION found, but >= 3.2 required"
            return 1
        fi
    fi
    return 1
}

install_ruby() {
    print_step "Ruby >= 3.2 not found. Installing..."

    # Install rbenv and ruby-build
    if [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install rbenv ruby-build
        else
            print_error "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    elif [[ "$OS" == "linux" ]]; then
        # Install rbenv via git
        if [ ! -d "$HOME/.rbenv" ]; then
            git clone https://github.com/rbenv/rbenv.git ~/.rbenv
            git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
        fi
        export PATH="$HOME/.rbenv/bin:$PATH"
        eval "$(rbenv init -)"
    fi

    print_step "Installing Ruby 3.3.0..."
    rbenv install 3.3.0
    rbenv global 3.3.0

    print_success "Ruby installed via rbenv"
}

# ============================================================================
# Configuration Helpers
# ============================================================================

get_config_path() {
    if [[ "$OS" == "macos" ]]; then
        echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    else
        echo "$HOME/.config/Claude/claude_desktop_config.json"
    fi
}

generate_remote_config() {
    # Pass --header and Authorization as separate args for proper parsing
    cat << EOF
{
  "mcpServers": {
    "smartsuite": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "$MCP_URL", "--header", "Authorization: Bearer $API_KEY"]
    }
  }
}
EOF
}

generate_local_config() {
    local server_path="$1"
    cat << EOF
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["$server_path/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "YOUR_SMARTSUITE_API_KEY",
        "SMARTSUITE_ACCOUNT_ID": "YOUR_SMARTSUITE_ACCOUNT_ID"
      }
    }
  }
}
EOF
}

configure_claude_desktop() {
    local config_json="$1"
    local config_path=$(get_config_path)
    local config_dir=$(dirname "$config_path")

    echo ""
    print_step "Configuring Claude Desktop"

    # Create directory if it doesn't exist
    mkdir -p "$config_dir"

    if [ -f "$config_path" ]; then
        # File exists - merge smartsuite into existing config
        print_step "Existing config found, merging smartsuite server..."

        # Use Python to merge JSON (available on macOS and most Linux)
        if command -v python3 &> /dev/null; then
            python3 << PYTHON
import json
import sys

# Read existing config
with open('$config_path', 'r') as f:
    try:
        existing = json.load(f)
    except json.JSONDecodeError:
        existing = {}

# Parse new config
new_config = json.loads('''$config_json''')

# Ensure mcpServers exists
if 'mcpServers' not in existing:
    existing['mcpServers'] = {}

# Add/update smartsuite
existing['mcpServers']['smartsuite'] = new_config['mcpServers']['smartsuite']

# Write back
with open('$config_path', 'w') as f:
    json.dump(existing, f, indent=2)

print("OK")
PYTHON
            if [ $? -eq 0 ]; then
                print_success "Config updated: $config_path"
            else
                print_error "Failed to merge config. Please add manually:"
                echo "$config_json"
            fi
        else
            print_warning "Python3 not found. Please add this to your config manually:"
            echo ""
            echo "$config_json"
        fi
    else
        # File doesn't exist - create it
        echo "$config_json" > "$config_path"
        print_success "Config created: $config_path"
    fi
}

# ============================================================================
# Installation Modes
# ============================================================================

install_remote() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     SmartSuite MCP Server - Remote Mode Installation      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Server URL: $MCP_URL"
    echo ""

    print_step "Detected OS: $OS"

    # Step 1: Ensure Node.js is installed
    if ! check_node; then
        install_node
        if ! check_node; then
            print_error "Node.js installation failed"
            exit 1
        fi
    fi

    # Step 2: Pre-cache mcp-remote
    print_step "Pre-caching mcp-remote package..."
    npx -y mcp-remote --version &> /dev/null || true
    print_success "mcp-remote ready"

    # Step 3: Configure Claude Desktop automatically
    configure_claude_desktop "$(generate_remote_config)"

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                    Installation Complete                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "  1. Restart Claude Desktop"
    echo "  2. Look for 'smartsuite' in the MCP servers list"
    echo "  3. Try: 'List my SmartSuite solutions'"
    echo ""
}

install_local() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      SmartSuite MCP Server - Local Mode Installation      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    print_step "Detected OS: $OS"

    # Step 1: Ensure Ruby is installed
    if ! check_ruby; then
        install_ruby
        if ! check_ruby; then
            print_error "Ruby installation failed"
            exit 1
        fi
    fi

    # Step 2: Clone or update repository
    INSTALL_DIR="$HOME/.smartsuite-mcp"

    if [ -d "$INSTALL_DIR" ]; then
        print_step "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull origin main
    else
        print_step "Cloning SmartSuite MCP server..."
        git clone https://github.com/Grupo-AFAL/smartsuite_mcp_server.git "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    # Step 3: Install dependencies
    print_step "Installing Ruby dependencies..."
    bundle install

    print_success "Server installed at: $INSTALL_DIR"

    # Step 4: Configure Claude Desktop automatically
    configure_claude_desktop "$(generate_local_config "$INSTALL_DIR")"

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                    Installation Complete                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "IMPORTANT: Update the config with your SmartSuite credentials:"
    echo "  - SMARTSUITE_API_KEY: From SmartSuite > Settings > API"
    echo "  - SMARTSUITE_ACCOUNT_ID: From your SmartSuite URL"
    echo ""
    echo "Next steps:"
    echo "  1. Add your SmartSuite credentials to the config"
    echo "  2. Restart Claude Desktop"
    echo "  3. Look for 'smartsuite' in the MCP servers list"
    echo "  4. Try: 'List my SmartSuite solutions'"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

case "$MODE" in
    local)
        install_local
        ;;
    remote)
        install_remote
        ;;
    *)
        print_error "Unknown mode: $MODE"
        echo ""
        show_usage
        exit 1
        ;;
esac
