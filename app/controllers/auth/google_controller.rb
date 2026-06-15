require "net/http"
require "json"

class Auth::GoogleController < AuthenticatedController
  skip_before_action :authenticate!, only: [:callback]

  SCOPE = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive.metadata.readonly",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/calendar.events"
  ].join(" ").freeze

  def connect
    redirect_to auth_url, allow_other_host: true
  end

  def callback
    @current_user ||= User.first if Rails.env.development?

    code = params[:code]
    if code.blank?
      redirect_to video_analyses_path, alert: "Google authorisation was denied or cancelled."
      return
    end

    tokens = exchange_code(code)
    if tokens["error"].present?
      redirect_to video_analyses_path, alert: "Google auth failed: #{tokens['error_description'] || tokens['error']}"
      return
    end

    expires_at = tokens["expires_in"] ? Time.current + tokens["expires_in"].to_i.seconds : nil

    current_user.update!(
      google_access_token:    tokens["access_token"],
      google_refresh_token:   tokens["refresh_token"] || current_user.google_refresh_token,
      google_token_expires_at: expires_at
    )

    redirect_to video_analyses_path, notice: "Google Drive connected."
  end

  def disconnect
    current_user.update!(
      google_access_token:     nil,
      google_refresh_token:    nil,
      google_token_expires_at: nil
    )
    redirect_to video_analyses_path, notice: "Google Drive disconnected."
  end

  private

  def auth_url
    params = {
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      redirect_uri:  auth_google_callback_url,
      response_type: "code",
      scope:         SCOPE,
      access_type:   "offline",
      prompt:        "consent",
      state:         "drive_connect"
    }
    "https://accounts.google.com/o/oauth2/v2/auth?" + params.to_query
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
end
