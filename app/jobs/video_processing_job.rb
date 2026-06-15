class VideoProcessingJob < ApplicationJob
  queue_as :transcription

  sidekiq_options retry: 3

  def perform(video_analysis_id,
              transcript_service: MeetTranscriptService,
              analysis_service:   ClaudeAnalysisService)
    analysis = VideoAnalysis.find(video_analysis_id)
    return if analysis.completed? || analysis.failed?

    if analysis.transcript.blank?
      if analysis.drive_file_id.present?
        transcribe_from_drive(analysis, transcript_service)
      else
        read_transcript_file(analysis)
      end
    end

    return if analysis.reload.failed?

    candidate = Candidate.find_by(video_analysis_id: analysis.id)
    unless candidate&.cv_analysis&.completed?
      analysis.transition_to!("awaiting_cv")
      return
    end

    analysis_service.new(analysis: analysis).call
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end

  private

  def transcribe_from_drive(analysis, transcript_service)
    transcript = transcript_service.new(analysis: analysis).call
    if transcript.present?
      analysis.update!(transcript: transcript)
    else
      analysis.transition_to!("failed",
        error: "No Google Meet transcript found. Ensure transcription was enabled for the recording.")
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
