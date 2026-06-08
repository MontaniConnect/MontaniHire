require "google/apis/drive_v3"
require "googleauth"
require "tempfile"

class DriveDownloadService
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

  def initialize(analysis)
    @analysis = analysis
  end

  def call
    @analysis.transition_to!("downloading")

    drive = authorized_drive_client
    file_metadata = drive.get_file(@analysis.drive_file_id, fields: "name,mimeType,size")
    @analysis.update!(drive_file_name: file_metadata.name) if @analysis.drive_file_name.blank?

    @temp_file = Tempfile.new(["video", ".mp4"], binmode: true)
    drive.get_file(@analysis.drive_file_id, download_dest: @temp_file)
    @temp_file.rewind

    @temp_file
  ensure
    # Caller is responsible for closing the tempfile; Sidekiq job manages lifecycle
  end

  def temp_file
    @temp_file
  end

  private

  def authorized_drive_client
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(ENV.fetch("GOOGLE_SERVICE_ACCOUNT_JSON")),
      scope: SCOPE
    )
    drive = Google::Apis::DriveV3::DriveService.new
    drive.authorization = credentials
    drive
  end
end
