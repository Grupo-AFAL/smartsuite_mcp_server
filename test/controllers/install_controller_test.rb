# frozen_string_literal: true

require "minitest/autorun"
require "rack/test"

# Load Rails application
ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"

class InstallControllerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  # GET /install tests

  def test_get_install_returns_success
    get "/install"
    assert last_response.ok?, "Expected 200, got #{last_response.status}"
  end

  def test_get_install_renders_html_page
    get "/install"
    assert_includes last_response.body, "Install SmartSuite MCP Server"
  end

  def test_get_install_detects_macos_from_user_agent
    get "/install", {}, { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }
    assert last_response.ok?
    assert_includes last_response.body, "Detected: Macos"
  end

  def test_get_install_detects_windows_from_user_agent
    get "/install", {}, { "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
    assert last_response.ok?
    assert_includes last_response.body, "Detected: Windows"
  end

  def test_get_install_detects_linux_from_user_agent
    get "/install", {}, { "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64)" }
    assert last_response.ok?
    assert_includes last_response.body, "Detected: Linux"
  end

  def test_get_install_shows_both_remote_and_local_modes
    get "/install"
    assert_includes last_response.body, "Remote Server"
    assert_includes last_response.body, "Local Server"
  end

  def test_get_install_includes_mcp_url
    get "/install"
    assert_includes last_response.body, "/mcp"
  end

  # GET /install.sh tests

  def test_get_install_sh_returns_success
    get "/install.sh"
    assert last_response.ok?, "Expected 200, got #{last_response.status}"
  end

  def test_get_install_sh_returns_shell_script_content_type
    get "/install.sh"
    assert_includes last_response.content_type, "text/x-shellscript"
  end

  def test_get_install_sh_returns_executable_script_content
    get "/install.sh"
    assert_includes last_response.body, "#!/bin/bash"
    assert_includes last_response.body, "SmartSuite MCP Server"
  end

  def test_get_install_sh_includes_local_and_remote_modes
    get "/install.sh"
    assert_includes last_response.body, "install_local"
    assert_includes last_response.body, "install_remote"
  end

  # GET /install.ps1 tests

  def test_get_install_ps1_returns_success
    get "/install.ps1"
    assert last_response.ok?, "Expected 200, got #{last_response.status}"
  end

  def test_get_install_ps1_returns_text_content_type
    get "/install.ps1"
    assert_includes last_response.content_type, "text/plain"
  end

  def test_get_install_ps1_returns_powershell_script_content
    get "/install.ps1"
    assert_includes last_response.body, "SmartSuite MCP Server"
    assert_includes last_response.body, "param("
  end

  def test_get_install_ps1_includes_local_and_remote_modes
    get "/install.ps1"
    assert_includes last_response.body, "Install-Local"
    assert_includes last_response.body, "Install-Remote"
  end
end
