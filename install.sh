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

# Detect user's shell and return the appropriate config file
detect_shell_profile() {
    local user_shell
    user_shell=$(basename "$SHELL")

    case "$user_shell" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            # On macOS, .bash_profile is preferred; on Linux, .bashrc
            if [[ "$OS_TYPE" == "macos" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            # Fallback: try to detect from existing files
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "$HOME/.zshrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            elif [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            else
                # Default to zsh on macOS (default since Catalina), bash on Linux
                if [[ "$OS_TYPE" == "macos" ]]; then
                    echo "$HOME/.zshrc"
                else
                    echo "$HOME/.bashrc"
                fi
            fi
            ;;
    esac
}

# Get the Homebrew Ruby path for the current system
get_homebrew_ruby_path() {
    if [[ -d "/opt/homebrew/opt/ruby/bin" ]]; then
        echo "/opt/homebrew/opt/ruby/bin"
    elif [[ -d "/usr/local/opt/ruby/bin" ]]; then
        echo "/usr/local/opt/ruby/bin"
    else
        # Ruby not yet installed, return expected path based on architecture
        if [[ "$(uname -m)" == "arm64" ]]; then
            echo "/opt/homebrew/opt/ruby/bin"
        else
            echo "/usr/local/opt/ruby/bin"
        fi
    fi
}

# Add Homebrew Ruby to PATH
add_homebrew_ruby_to_path() {
    local ruby_path
    ruby_path=$(get_homebrew_ruby_path)

    # Add Ruby to PATH for current session
    if [[ -d "$ruby_path" ]]; then
        export PATH="$ruby_path:$PATH"
    fi
}

# Add PATH configuration to shell profile
add_path_to_shell_profile() {
    local ruby_path="$1"
    local shell_profile
    shell_profile=$(detect_shell_profile)

    print_info "Detected shell: $(basename "$SHELL")"
    print_info "Shell profile: $shell_profile"

    # Create the shell profile if it doesn't exist
    if [[ ! -f "$shell_profile" ]]; then
        print_info "Creating $shell_profile..."
        touch "$shell_profile"
    fi

    # Create parent directory for fish config if needed
    if [[ "$shell_profile" == *"fish"* ]] && [[ ! -d "$(dirname "$shell_profile")" ]]; then
        mkdir -p "$(dirname "$shell_profile")"
    fi

    # Check if already added (check for both possible paths)
    if grep -q "homebrew/opt/ruby/bin" "$shell_profile" 2>/dev/null; then
        print_info "Homebrew Ruby PATH already configured in $shell_profile"
        return
    fi

    print_info "Adding Homebrew Ruby to PATH in $shell_profile..."

    # Add appropriate syntax based on shell type
    if [[ "$shell_profile" == *"fish"* ]]; then
        echo "set -gx PATH $ruby_path \$PATH" >> "$shell_profile"
    else
        echo "export PATH=\"$ruby_path:\$PATH\"" >> "$shell_profile"
    fi

    print_success "PATH configured in $shell_profile"
}

# Install Ruby via Homebrew on macOS
install_ruby_macos() {
    print_info "Installing Ruby using Homebrew..."
    brew install ruby

    local ruby_path
    ruby_path=$(get_homebrew_ruby_path)

    # Add to PATH for current session
    export PATH="$ruby_path:$PATH"

    # Add to shell profile for future sessions
    add_path_to_shell_profile "$ruby_path"

    print_success "Ruby installed via Homebrew"
}

# Check Ruby version meets requirements
check_ruby_version() {
    local ruby_path="$1"
    local ruby_version
    ruby_version=$("$ruby_path" -v | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local required_version="3.0"

    if awk -v ver="$ruby_version" -v req="$required_version" 'BEGIN { exit !(ver >= req) }'; then
        echo "$ruby_version"
        return 0
    else
        return 1
    fi
}

# Check for Ruby installation
check_ruby() {
    print_header "Checking Ruby Installation"

    REQUIRED_VERSION="3.0"

    # First, check if Homebrew Ruby is available (prefer it over system Ruby)
    if [[ "$OS_TYPE" == "macos" ]]; then
        add_homebrew_ruby_to_path
    fi

    # Check if Ruby is installed and meets version requirements
    if command -v ruby &> /dev/null; then
        RUBY_VERSION=$(ruby -v | grep -oE '[0-9]+\.[0-9]+' | head -1)

        if awk -v ver="$RUBY_VERSION" -v req="$REQUIRED_VERSION" 'BEGIN { exit !(ver >= req) }'; then
            print_success "Ruby $RUBY_VERSION is installed"
            return
        else
            print_warning "Ruby version $RUBY_VERSION is installed, but version $REQUIRED_VERSION or higher is required."
        fi
    else
        print_warning "Ruby is not installed."
    fi

    # Ruby not found or version too old - install on macOS, show instructions on Linux
    if [[ "$OS_TYPE" == "macos" ]]; then
        install_ruby_macos

        # Verify installation
        if command -v ruby &> /dev/null; then
            RUBY_VERSION=$(ruby -v | grep -oE '[0-9]+\.[0-9]+' | head -1)
            if awk -v ver="$RUBY_VERSION" -v req="$REQUIRED_VERSION" 'BEGIN { exit !(ver >= req) }'; then
                print_success "Ruby $RUBY_VERSION is now installed"
                return
            fi
        fi

        print_error "Failed to install Ruby $REQUIRED_VERSION or higher."
        print_info "Please try manually: brew install ruby"
        print_info "Then add to your PATH: export PATH=\"/opt/homebrew/opt/ruby/bin:\$PATH\""
        exit 1
    elif [[ "$OS_TYPE" == "linux" ]]; then
        print_error "Ruby $REQUIRED_VERSION or higher is required."
        print_info "Please install Ruby using your package manager:"
        echo "  Ubuntu/Debian: sudo apt-get install ruby-full"
        echo "  Fedora/RHEL: sudo dnf install ruby"
        echo "  Or use rbenv/rvm for version management"
        exit 1
    fi
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
