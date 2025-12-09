# frozen_string_literal: true

# Dynamic Client Registration (RFC 7591)
# Allows OAuth clients like Claude Desktop to register automatically
class OAuthRegistrationsController < ApplicationController
  # POST /oauth/register
  def create
    # Validate required fields
    unless registration_params[:client_name].present?
      return render json: { error: "invalid_client_metadata",
                            error_description: "client_name is required" }, status: :bad_request
    end

    unless registration_params[:redirect_uris].is_a?(Array) && registration_params[:redirect_uris].any?
      return render json: { error: "invalid_redirect_uri",
                            error_description: "redirect_uris must be a non-empty array" }, status: :bad_request
    end

    # Check for existing client with same name and redirect_uris
    existing = Doorkeeper::Application.find_by(
      name: registration_params[:client_name],
      redirect_uri: registration_params[:redirect_uris].join("\n")
    )

    if existing
      # Return existing client credentials (idempotent registration)
      render json: client_response(existing), status: :ok
    else
      # Create new OAuth application
      application = Doorkeeper::Application.new(
        name: registration_params[:client_name],
        redirect_uri: registration_params[:redirect_uris].join("\n"),
        scopes: "read write",
        confidential: true
      )

      if application.save
        render json: client_response(application), status: :created
      else
        render json: {
          error: "invalid_client_metadata",
          error_description: application.errors.full_messages.join(", ")
        }, status: :bad_request
      end
    end
  end

  private

  def registration_params
    @registration_params ||= begin
      parsed = JSON.parse(request.body.read)
      parsed.with_indifferent_access
    end
  rescue JSON::ParserError
    {}
  end

  def client_response(application)
    {
      client_id: application.uid,
      client_secret: application.secret,
      client_name: application.name,
      redirect_uris: application.redirect_uri.split("\n"),
      grant_types: %w[authorization_code refresh_token],
      response_types: %w[code],
      token_endpoint_auth_method: "client_secret_basic"
    }
  end
end
