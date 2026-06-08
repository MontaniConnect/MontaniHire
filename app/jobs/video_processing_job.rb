class VideoProcessingJob < ApplicationJob
  queue_as :transcription

  sidekiq_options retry: 3

  def perform(video_analysis_id)
    analysis = VideoAnalysis.find(video_analysis_id)
    return if analysis.completed? || analysis.failed?

    WhisperTranscriptionService.new(analysis).call if analysis.transcript.blank?

    candidate = Candidate.find_by(video_analysis_id: analysis.id)
    unless candidate&.cv_analysis&.completed?
      analysis.transition_to!("awaiting_cv")
      return
    end

    ClaudeAnalysisService.new(analysis).call
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end
end
