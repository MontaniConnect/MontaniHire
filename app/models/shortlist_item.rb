class ShortlistItem < ApplicationRecord
  belongs_to :shortlist
  belongs_to :shareable,      polymorphic: true, optional: true
  belongs_to :candidate,      optional: true
  belongs_to :cv_analysis,    optional: true, class_name: "CvAnalysis"
  belongs_to :video_analysis, optional: true, class_name: "VideoAnalysis"
  belongs_to :added_by,       optional: true, class_name: "User"

  STATUSES = %w[pending approved rejected].freeze
  validates :client_status, inclusion: { in: STATUSES }
  validate :candidate_client_matches_shortlist

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

  def role_title
    job_role&.title
  end

  def score
    candidate&.score ||
      cv_analysis&.cv_fit_score ||
      video_analysis&.episode_score ||
      (shareable.is_a?(CvAnalysis)    ? shareable.cv_fit_score    : nil) ||
      (shareable.is_a?(VideoAnalysis) ? shareable.episode_score   : nil)
  end

  def summary
    candidate&.summary ||
      cv_analysis&.summary ||
      video_analysis&.summary ||
      shareable&.summary
  end

  def client_summary
    candidate&.cv_analysis&.client_summary ||
      candidate&.video_analysis&.client_summary ||
      cv_analysis&.client_summary ||
      video_analysis&.client_summary ||
      (shareable.respond_to?(:client_summary) ? shareable.client_summary : nil)
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

  def self.hm_decided_for_role(role, exclude: nil)
    q = joins(:candidate)
          .where(client_status: %w[approved rejected])
          .where(candidates: { job_role_id: role.id })
          .includes(candidate: [ :cv_analysis, :video_analysis ])
          .order(updated_at: :desc)
    q = q.where.not(candidates: { id: exclude.id }) if exclude
    q.limit(12).to_a.uniq { |i| i.candidate_id }.first(6)
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

  private

  def candidate_client_matches_shortlist
    candidate_client = candidate&.job_role&.client_id
    shortlist_client = shortlist&.client_id
    return unless candidate_client.present? && shortlist_client.present?
    if candidate_client != shortlist_client
      errors.add(:candidate, "belongs to a different client's pipeline and cannot be added to this shortlist")
    end
  end
end
