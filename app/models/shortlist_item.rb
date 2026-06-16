class ShortlistItem < ApplicationRecord
  belongs_to :shortlist
  belongs_to :shareable,      polymorphic: true, optional: true
  belongs_to :candidate,      optional: true
  belongs_to :cv_analysis,    optional: true, class_name: "CvAnalysis"
  belongs_to :video_analysis, optional: true, class_name: "VideoAnalysis"

  STATUSES = %w[pending approved rejected].freeze
  validates :client_status, inclusion: { in: STATUSES }

  def candidate_name
    candidate&.name ||
      cv_analysis&.display_name ||
      video_analysis&.display_name ||
      shareable&.display_name
  end

  def job_role
    candidate&.job_role ||
      cv_analysis&.job_role ||
      video_analysis&.job_role ||
      shareable&.job_role
  end

  def score
    candidate&.score ||
      cv_analysis&.score ||
      video_analysis&.score ||
      shareable&.score
  end

  def summary
    candidate&.summary ||
      cv_analysis&.summary ||
      video_analysis&.summary ||
      shareable&.summary
  end

  def structured_feedback
    candidate&.structured_feedback ||
      cv_analysis&.structured_feedback ||
      video_analysis&.structured_feedback ||
      shareable&.structured_feedback ||
      {}
  end

  def resolved_cv_analysis
    candidate&.cv_analysis || cv_analysis ||
      (shareable.is_a?(CvAnalysis) ? shareable : nil)
  end

  def resolved_video_analysis
    candidate&.video_analysis || video_analysis ||
      (shareable.is_a?(VideoAnalysis) ? shareable : nil)
  end

  def sync_candidate_stage!(client_status)
    stage = Candidate.stage_for_client_status(client_status)
    # update_columns bypasses after_save to prevent circular sync
    candidate&.update_columns(pipeline_stage: stage) if stage
  end

  def toggle_final_interview_no_show!
    candidate&.update_columns(
      final_interview_no_show: !candidate.final_interview_no_show
    )
  end

  def final_interview_no_show? = candidate&.final_interview_no_show || false

  def kind
    parts = []
    parts << "CV"    if resolved_cv_analysis.present?
    parts << "Video" if resolved_video_analysis.present?
    parts.any? ? parts.join(" + ") : "—"
  end
end
