class CvProcessingJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: 3

  def perform(cv_analysis_id,
              extraction_service: CvTextExtractionService,
              analysis_service:   CvClaudeAnalysisService)
    analysis = CvAnalysis.find(cv_analysis_id)
    return if analysis.completed? || analysis.failed?

    extraction_service.new(analysis: analysis).call
    analysis_service.new(analysis: analysis).call

    candidate = analysis.candidate
    if candidate && candidate.email.blank?
      # Collapse line breaks inside split email addresses (common in multi-column PDFs)
      searchable = analysis.extracted_text&.gsub(/([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+)\n+([A-Za-z0-9.\-]{1,6})/) { |_m| $1 + $2 }
      email_match = searchable&.match(/\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/)
      candidate.update_columns(email: email_match[0]) if email_match
    end

    if candidate&.video_analysis&.awaiting_cv?
      VideoProcessingJob.perform_later(candidate.video_analysis.id)
    end
  rescue User::GoogleTokenRevoked => e
    # Retrying won't help — the refresh token is revoked. Fail fast.
    analysis&.transition_to!("failed",
      error: "Google account disconnected. Reconnect it in Settings and re-submit. (#{e.message})")
  rescue => e
    analysis&.transition_to!("failed", error: e.message)
    raise
  end
end
