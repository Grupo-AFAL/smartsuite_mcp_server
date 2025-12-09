# frozen_string_literal: true

# Handles user authentication for OAuth flows
class SessionsController < OAuthBaseController
  layout "oauth"
  def new
    # Preserve OAuth params through login flow
    session[:oauth_params] = params.permit(:client_id, :redirect_uri, :response_type, :scope, :state,
                                           :code_challenge, :code_challenge_method).to_h
    @oauth_flow = session[:oauth_params].present? && session[:oauth_params][:client_id].present?
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id

      # Redirect back to OAuth authorization if we came from there
      if session[:oauth_params].present? && session[:oauth_params][:client_id].present?
        oauth_params = session.delete(:oauth_params)
        redirect_to oauth_authorization_path(oauth_params)
      else
        redirect_to root_path, notice: "Logged in successfully"
      end
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to root_path, notice: "Logged out successfully"
  end
end
