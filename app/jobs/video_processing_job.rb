class VideoProcessingJob < ApplicationJob
  queue_as :transcription

  sidekiq_options retry: 3

  def perform(video_analysis_id,
              transcript_service: DriveTranscriptionService,
              analysis_service:   ClaudeAnalysisService,
              highlight_service:  SegmentHighlightService)
    analysis = VideoAnalysis.find(video_analysis_id)
    return if analysis.completed? || analysis.failed?

    if analysis.transcript.blank?
      if analysis.drive_file_id.present?
        transcript = transcript_service.new(analysis: analysis).call
        if transcript.present?
          analysis.update!(transcript: transcript)
        else
          analysis.transition_to!("failed",
            error: "No Google Meet transcript found. Ensure transcription was enabled for the recording.")
        end
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
    candidate.advance_to_interview! if candidate&.pipeline_stage == "cv_review"
    begin
      highlight_service.new(analysis: analysis).call
    rescue => e
      Rails.logger.warn "[VideoProcessingJob] SegmentHighlightService failed: #{e.class}: #{e.message}"
    end
  rescue User::GoogleTokenRevoked => e
    # Retrying won't help — the refresh token is revoked. Fail fast.
    analysis&.transition_to!("failed",
      error: "Google account disconnected. Reconnect it in Settings and re-submit. (#{e.message})")
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end

  private

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

    raw = blob.download

    if blob.filename.to_s.end_with?(".vtt")
      parser   = TranscriptParsers::Vtt.new
      text     = parser.parse(raw)
      segments = parser.parse_segments(raw)
      analysis.update!(transcript: text, transcript_segments: segments)
    else
      analysis.update!(transcript: TranscriptParsers::PlainText.new.parse(raw))
    end

    analysis.video.purge_later
  end
end
