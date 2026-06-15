require "tempfile"

class DriveDownloadService
  def initialize(analysis)
    @analysis = analysis
  end

  def call
    @analysis.transition_to!("downloading")

    drive = GoogleDriveClient.for(@analysis.user)
    meta  = drive.get_file(@analysis.drive_file_id, fields: "name,mimeType,size")
    @analysis.update!(drive_file_name: meta.name) if @analysis.drive_file_name.blank?

    @temp_file = Tempfile.new(["video", ".mp4"], binmode: true)
    drive.get_file(@analysis.drive_file_id, download_dest: @temp_file)
    @temp_file.rewind
    @temp_file
  ensure
    # Caller manages lifecycle
  end

  def temp_file = @temp_file
end
