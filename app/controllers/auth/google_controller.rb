require "net/http"
require "json"

class Auth::GoogleController < ApplicationController
  before_action :authenticate!, only: [:connect, :disconnect]

  SCOPE = [
    "openid",
    "email",
    "profile",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive.metadata.readonly",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/calendar.events"
  ].join(" ").freeze

  def login
    redirect_to auth_url(state: "login"), allow_other_host: true
  end

  def connect
    redirect_to auth_url(state: "connect"), allow_other_host: true
  end

  def callback
    code = params[:code]
    if code.blank?
      redirect_to login_path, alert: "Google authorisation was denied or cancelled."
      return
    end

    tokens = exchange_code(code)
    if tokens["error"].present?
      redirect_to login_path, alert: "Google auth failed: #{tokens['error_description'] || tokens['error']}"
      return
    end

    info       = decode_id_token(tokens["id_token"])
    email      = info["email"]
    expires_at = tokens["expires_in"] ? Time.current + tokens["expires_in"].to_i.seconds : nil

    if current_user
      current_user.update!(
        google_access_token:     tokens["access_token"],
        google_refresh_token:    tokens["refresh_token"] || current_user.google_refresh_token,
        google_token_expires_at: expires_at
      )
      redirect_to settings_path, notice: "Google account reconnected."
    else
      unless email.present?
        redirect_to login_path, alert: "Could not retrieve your email from Google. Please try again."
        return
      end

      user = User.find_or_initialize_by(email: email)
      user.name = info["name"] if user.name.blank?
      user.google_access_token     = tokens["access_token"]
      user.google_refresh_token    = tokens["refresh_token"] || user.google_refresh_token
      user.google_token_expires_at = expires_at
      user.save!

      session[:user_id] = user.id
      redirect_to session.delete(:return_to) || root_path,
                  notice: "Signed in as #{user.name.presence || user.email}."
    end
  end

  def disconnect
    current_user.update!(
      google_access_token:     nil,
      google_refresh_token:    nil,
      google_token_expires_at: nil
    )
    redirect_to settings_path, notice: "Google account disconnected."
  end

  private

  def auth_url(state:)
    query = {
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      redirect_uri:  auth_google_callback_url,
      response_type: "code",
      scope:         SCOPE,
      access_type:   "offline",
      prompt:        "consent",
      state:         state
    }
    "https://accounts.google.com/o/oauth2/v2/auth?" + query.to_query
  end

  def exchange_code(code)
    uri  = URI("https://oauth2.googleapis.com/token")
    body = {
      code:          code,
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
      redirect_uri:  auth_google_callback_url,
      grant_type:    "authorization_code"
    }
    response = Net::HTTP.post_form(uri, body)
    JSON.parse(response.body)
  end

  def decode_id_token(id_token)
    return {} unless id_token
    payload = id_token.split(".")[1].to_s
    padded  = payload + "=" * ((4 - payload.length % 4) % 4)
    JSON.parse(Base64.urlsafe_decode64(padded))
  rescue
    {}
  end
end
