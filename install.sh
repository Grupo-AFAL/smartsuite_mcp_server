#!/bin/bash

# SmartSuite MCP Server - Installation Script (macOS/Linux)
# This script helps users set up the SmartSuite MCP server for Claude Desktop
# on macOS and Linux without requiring coding knowledge.
#
# For Windows, please use install.ps1 instead.

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
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

# Check operating system
check_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        print_info "Detected: macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
        OS_TYPE="linux"
        print_info "Detected: Linux"
    else
        print_error "This script is only supported on macOS and Linux."
        print_info "For Windows, please use install.ps1"
        print_info "For other operating systems, please refer to the manual installation instructions."
        exit 1
    fi
}

# Install Homebrew on macOS if not present
install_homebrew() {
    if [[ "$OS_TYPE" != "macos" ]]; then
        return
    fi

    if ! command -v brew &> /dev/null; then
        print_header "Installing Homebrew"
        print_info "Homebrew is not installed. Installing now..."
        print_warning "You may be prompted for your password."

        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi

        print_success "Homebrew installed successfully"
    else
        print_success "Homebrew is already installed"
    fi
}

# Check for Ruby installation
check_ruby() {
    print_header "Checking Ruby Installation"

    if ! command -v ruby &> /dev/null; then
        print_error "Ruby is not installed."

        if [[ "$OS_TYPE" == "macos" ]]; then
            print_info "Installing Ruby using Homebrew..."
            brew install ruby

            # Add Ruby to PATH for current session
            if [[ -d "/opt/homebrew/opt/ruby/bin" ]]; then
                export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
            elif [[ -d "/usr/local/opt/ruby/bin" ]]; then
                export PATH="/usr/local/opt/ruby/bin:$PATH"
            fi
        elif [[ "$OS_TYPE" == "linux" ]]; then
            print_info "Please install Ruby 3.0+ using your package manager:"
            echo "  Ubuntu/Debian: sudo apt-get install ruby-full"
            echo "  Fedora/RHEL: sudo dnf install ruby"
            echo "  Or use rbenv/rvm for version management"
            exit 1
        fi
    fi

    RUBY_VERSION=$(ruby -v | grep -oE '[0-9]+\.[0-9]+' | head -1)
    REQUIRED_VERSION="3.0"

    if ! awk -v ver="$RUBY_VERSION" -v req="$REQUIRED_VERSION" 'BEGIN { exit !(ver >= req) }'; then
        print_error "Ruby version $RUBY_VERSION is installed, but version $REQUIRED_VERSION or higher is required."

        if [[ "$OS_TYPE" == "macos" ]]; then
            print_info "Please upgrade Ruby using: brew upgrade ruby"
        elif [[ "$OS_TYPE" == "linux" ]]; then
            print_info "Please upgrade Ruby using your package manager or rbenv/rvm"
        fi
        exit 1
    fi

    print_success "Ruby $RUBY_VERSION is installed"
}

# Install dependencies
install_dependencies() {
    print_header "Installing Dependencies"

    # Install bundler if not present
    if ! command -v bundle &> /dev/null; then
        print_info "Installing Bundler..."
        gem install bundler
    fi

    print_info "Installing gem dependencies..."
    bundle install

    print_success "All dependencies installed"
}

# Get SmartSuite credentials
get_credentials() {
    print_header "SmartSuite API Credentials"

    echo "To use this MCP server, you need SmartSuite API credentials."
    echo ""
    print_info "You can find your credentials at:"
    echo "  https://app.smartsuite.com/settings/api"
    echo ""

    # Prompt for API key
    while true; do
        read -p "Enter your SmartSuite API Key: " API_KEY
        if [[ -n "$API_KEY" ]]; then
            break
        else
            print_warning "API Key cannot be empty. Please try again."
        fi
    done

    # Prompt for Account ID
    while true; do
        read -p "Enter your SmartSuite Account ID: " ACCOUNT_ID
        if [[ -n "$ACCOUNT_ID" ]]; then
            break
        else
            print_warning "Account ID cannot be empty. Please try again."
        fi
    done

    print_success "Credentials configured"
}

# Configure Claude Desktop
configure_claude_desktop() {
    print_header "Configuring Claude Desktop"

    CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
    CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create config directory if it doesn't exist
    if [[ ! -d "$CLAUDE_CONFIG_DIR" ]]; then
        print_info "Creating Claude Desktop config directory..."
        mkdir -p "$CLAUDE_CONFIG_DIR"
    fi

    # Backup existing config if present
    if [[ -f "$CLAUDE_CONFIG_FILE" ]]; then
        BACKUP_FILE="${CLAUDE_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backing up existing configuration to: $BACKUP_FILE"
        cp "$CLAUDE_CONFIG_FILE" "$BACKUP_FILE"

        # Read existing config
        EXISTING_CONFIG=$(cat "$CLAUDE_CONFIG_FILE")
    else
        EXISTING_CONFIG='{}'
    fi

    # Create/update MCP server configuration
    print_info "Adding SmartSuite MCP server to Claude Desktop configuration..."

    # Use jq if available, otherwise manual JSON manipulation
    if command -v jq &> /dev/null; then
        # Add SmartSuite server to existing config
        echo "$EXISTING_CONFIG" | jq \
            --arg dir "$SCRIPT_DIR" \
            --arg api_key "$API_KEY" \
            --arg account_id "$ACCOUNT_ID" \
            '.mcpServers.smartsuite = {
                "command": "ruby",
                "args": [($dir + "/smartsuite_server.rb")],
                "env": {
                    "SMARTSUITE_API_KEY": $api_key,
                    "SMARTSUITE_ACCOUNT_ID": $account_id
                }
            }' > "$CLAUDE_CONFIG_FILE"
    else
        # Manual JSON construction (fallback if jq not available)
        cat > "$CLAUDE_CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "smartsuite": {
      "command": "ruby",
      "args": ["$SCRIPT_DIR/smartsuite_server.rb"],
      "env": {
        "SMARTSUITE_API_KEY": "$API_KEY",
        "SMARTSUITE_ACCOUNT_ID": "$ACCOUNT_ID"
      }
    }
  }
}
EOF
    fi

    print_success "Claude Desktop configured"
    print_info "Configuration file: $CLAUDE_CONFIG_FILE"
}

# Make server executable
make_executable() {
    print_header "Making Server Executable"

    chmod +x smartsuite_server.rb

    print_success "Server is now executable"
}

# Final instructions
print_final_instructions() {
    print_header "Installation Complete! 🎉"

    echo "The SmartSuite MCP server has been successfully installed and configured."
    echo ""
    print_info "Next steps:"
    echo "  1. Restart Claude Desktop to load the new MCP server"
    echo "  2. In Claude Desktop, you should see SmartSuite tools available"
    echo "  3. Try asking Claude: 'List my SmartSuite solutions'"
    echo ""
    print_info "Configuration location:"
    echo "  $HOME/Library/Application Support/Claude/claude_desktop_config.json"
    echo ""
    print_info "For troubleshooting, see:"
    echo "  docs/getting-started/troubleshooting.md"
    echo ""
    print_success "Enjoy using SmartSuite with Claude! 🚀"
}

# Main installation flow
main() {
    clear

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║        SmartSuite MCP Server Installation Script          ║"
    echo "║                   (macOS / Linux)                          ║"
    echo "║                                                            ║"
    echo "║  This script will help you set up the SmartSuite MCP      ║"
    echo "║  server for use with Claude Desktop.                      ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    print_info "Press Enter to begin installation, or Ctrl+C to cancel"
    read -r

    # Run installation steps
    check_os
    install_homebrew  # Install Homebrew first on macOS (if needed)
    check_ruby
    install_dependencies
    get_credentials
    make_executable
    configure_claude_desktop
    print_final_instructions
}

# Run main function
main
