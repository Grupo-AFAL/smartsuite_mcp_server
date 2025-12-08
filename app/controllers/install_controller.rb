# frozen_string_literal: true

# Serves installation instructions and scripts for MCP client setup
class InstallController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :script ]

  # GET /install - Installation page with OS detection
  def show
    @os = detect_os
    @base_url = request.base_url
    @mcp_url = "#{@base_url}/mcp"
  end

  # GET /install.sh - Unix installation script
  def script_sh
    send_file Rails.root.join("bin/install/install.sh"),
              type: "text/x-shellscript",
              disposition: "inline",
              filename: "install.sh"
  end

  # GET /install.ps1 - Windows installation script
  def script_ps1
    send_file Rails.root.join("bin/install/install.ps1"),
              type: "text/plain",
              disposition: "inline",
              filename: "install.ps1"
  end

  private

  def detect_os
    user_agent = request.user_agent.to_s.downcase

    if user_agent.include?("windows")
      :windows
    elsif user_agent.include?("mac")
      :macos
    elsif user_agent.include?("linux")
      :linux
    else
      :unknown
    end
  end
end
