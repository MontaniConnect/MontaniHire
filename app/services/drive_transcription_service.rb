class DriveTranscriptionService
  def initialize(analysis:)
    @analysis = analysis
  end

  def call
    drive = GoogleDriveClient.for(@analysis.user)
    meta  = drive.get_file(@analysis.drive_file_id, fields: "mimeType,name")

    if meta.mime_type.start_with?("video/", "audio/")
      transcribe_video(drive, meta)
    else
      MeetTranscriptService.new(analysis: @analysis).call
    end
  end

  private

  def transcribe_video(drive, meta)
    ext = File.extname(meta.name.to_s).presence || ".mp4"
    tmp = Tempfile.new(["drive_video", ext], binmode: true)
    begin
      drive.get_file(@analysis.drive_file_id, download_dest: tmp)
      tmp.rewind
      result = WhisperTranscriptionService.new(analysis: @analysis).call(video_tmp: tmp)
      @analysis.update_columns(drive_video_file_id: @analysis.drive_file_id)
      result
    rescue Google::Apis::ClientError => e
      if e.status_code == 403
        raise "Google Drive blocked the download (403). The file \"#{meta.name}\" may have download restrictions set by a Google Workspace admin or was shared as view-only. Open the file in Google Drive and ensure download is permitted, or download it manually and upload here directly."
      end
      raise
    ensure
      tmp.close
      tmp.unlink
    end
  end
end
