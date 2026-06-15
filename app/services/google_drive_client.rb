require "google/apis/drive_v3"
require "googleauth"

module GoogleDriveClient
  SA_SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

  def self.for(user)
    drive = Google::Apis::DriveV3::DriveService.new
    drive.authorization = credentials_for(user)
    drive
  end

  def self.credentials_for(user)
    if user&.google_connected?
      Google::Auth::UserRefreshCredentials.new(
        client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
        refresh_token: user.google_refresh_token,
        access_token:  user.fresh_google_access_token
      )
    else
      sa_json = ENV["GOOGLE_SERVICE_ACCOUNT_JSON"].presence
      raise "No Google credentials available. Connect your Google account or configure GOOGLE_SERVICE_ACCOUNT_JSON." unless sa_json
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(sa_json),
        scope: SA_SCOPE
      )
    end
  end
end
