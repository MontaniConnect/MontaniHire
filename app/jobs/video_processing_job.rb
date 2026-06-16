class VideoProcessingJob < ApplicationJob
  queue_as :transcription

  sidekiq_options retry: 3

  def perform(video_analysis_id, analysis_service: ClaudeAnalysisService)
    analysis = VideoAnalysis.find(video_analysis_id)
    return if analysis.completed? || analysis.failed?

    if analysis.transcript.blank?
      if analysis.drive_file_id.present?
        transcribe_from_drive(analysis)
      else
        transcribe_from_file(analysis)
      end
    end

    return if analysis.reload.failed?

    candidate = Candidate.find_by(video_analysis_id: analysis.id)
    unless candidate&.cv_ready?
      analysis.transition_to!("awaiting_cv")
      return
    end

    analysis_service.new(analysis: analysis).call
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end

  private

  def transcribe_from_drive(analysis)
    drive = GoogleDriveClient.for(analysis.user)
    meta  = drive.get_file(analysis.drive_file_id, fields: "mimeType,name")

    if meta.mime_type.start_with?("video/", "audio/")
      ext = File.extname(meta.name.to_s).presence || ".mp4"
      tmp = Tempfile.new(["drive_video", ext], binmode: true)
      begin
        drive.get_file(analysis.drive_file_id, download_dest: tmp)
        tmp.rewind
        WhisperTranscriptionService.new(analysis: analysis).call(video_tmp: tmp)
        analysis.update_columns(drive_video_file_id: analysis.drive_file_id)
      rescue Google::Apis::ClientError => e
        if e.status_code == 403
          raise "Google Drive blocked the download (403). The file \"#{meta.name}\" may have download restrictions set by a Google Workspace admin or was shared as view-only. Open the file in Google Drive and ensure download is permitted, or download it manually and upload here directly."
        end
        raise
      ensure
        tmp.close
        tmp.unlink
      end
    else
      transcript = MeetTranscriptService.new(analysis: analysis).call
      if transcript.present?
        analysis.update!(transcript: transcript)
      else
        analysis.transition_to!("failed",
          error: "No Google Meet transcript found. Ensure transcription was enabled for the recording.")
      end
    end
  end

  def transcribe_from_file(analysis)
    blob = analysis.video.blob
    raise "No file attached." unless blob

    if blob.content_type.to_s.start_with?("video/", "audio/")
      WhisperTranscriptionService.new(analysis: analysis).call
    else
      read_transcript_file(analysis)
    end
  end

  def read_transcript_file(analysis)
    blob = analysis.video.blob
    raise "No transcript file attached." unless blob

    raw        = blob.download
    mime_type  = blob.filename.to_s.end_with?(".vtt") ? TranscriptParsers::Vtt::MIME_TYPE : "text/plain"
    transcript = TranscriptParsers.for(mime_type).parse(raw)

    analysis.update!(transcript: transcript)
    analysis.video.purge_later
  end
end
