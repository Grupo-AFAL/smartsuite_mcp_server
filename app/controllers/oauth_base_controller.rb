# frozen_string_literal: true

# Base controller for OAuth endpoints
# Provides session support needed for OAuth authorization flow
class OAuthBaseController < ActionController::Base
  protect_from_forgery with: :exception

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
