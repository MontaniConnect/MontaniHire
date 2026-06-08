class CvProcessingJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: 3

  def perform(cv_analysis_id)
    analysis = CvAnalysis.find(cv_analysis_id)
    return if analysis.completed? || analysis.failed?

    CvTextExtractionService.new(analysis).call
    CvClaudeAnalysisService.new(analysis).call

    candidate = analysis.candidate
    if candidate&.video_analysis&.awaiting_cv?
      VideoProcessingJob.perform_later(candidate.video_analysis.id)
    end
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end
end
