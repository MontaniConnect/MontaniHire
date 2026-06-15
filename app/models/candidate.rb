class Candidate < ApplicationRecord
  belongs_to :user
  belongs_to :job_role, optional: true
  belongs_to :cv_analysis,    optional: true, class_name: "CvAnalysis"
  belongs_to :video_analysis, optional: true, class_name: "VideoAnalysis"
  has_many   :shortlist_items, dependent: :nullify
  has_one    :slot_booking,   dependent: :destroy

  STAGES = %w[cv_review preliminary_interview client_interview final_interview not_invited rejected hired offer_declined not_selected].freeze


  validates :name, presence: true

  def name
    self[:name]&.titleize
  end
  validates :pipeline_stage, inclusion: { in: STAGES }

  def advance_to_interview!
    update!(pipeline_stage: "preliminary_interview",
            interviewed_at: interviewed_at || Time.current)
  end

  def advance_to_final_interview!
    update!(pipeline_stage: "final_interview",
            final_interview_at: final_interview_at || Time.current)
  end

  def mark_not_invited!
    update!(pipeline_stage: "not_invited")
  end

  def hire!
    update!(pipeline_stage: "hired", hired_at: hired_at || Time.current)
  end

  def shortlist_for_client!
    update!(pipeline_stage: "client_interview",
            shortlisted_at: shortlisted_at || Time.current)
  end

  def no_show!
    update!(no_show: true)
  end

  def undo_no_show!
    update!(no_show: false)
  end

  def mark_offer_declined!
    update!(pipeline_stage: "offer_declined")
  end

  def mark_not_selected!
    update!(pipeline_stage: "not_selected")
  end

  def intake_submitted? = intake_submitted_at.present?
  def intake_unread?    = intake_submitted? && intake_viewed_at.nil?

  def outcome_confirmed? = outcome_confirmed_at.present?
  def confirm_outcome!   = update!(outcome_confirmed_at: Time.current)
  def unconfirm_outcome! = update!(outcome_confirmed_at: nil)

  def revert!
    was_shortlisted = pipeline_stage == "client_interview"
    previous = {
      "preliminary_interview" => "cv_review",
      "client_interview"      => "preliminary_interview",
      "final_interview"       => "client_interview",
      "not_invited"           => "client_interview",
      "hired"                 => "final_interview",
      "offer_declined"        => "final_interview",
      "not_selected"          => "cv_review"
    }
    update!(pipeline_stage: previous.fetch(pipeline_stage, "cv_review"), outcome_confirmed_at: nil)
    shortlist_items.destroy_all if was_shortlisted
  end

  def reject!
    was_shortlisted = pipeline_stage == "client_interview"
    update!(pipeline_stage: "rejected")
    shortlist_items.destroy_all if was_shortlisted
  end

  EPISODE_WEIGHTS     = VideoAnalysis::EPISODE_WEIGHTS
  EPISODE_LEVEL_VALUES = VideoAnalysis::EPISODE_LEVEL_VALUES

  def episode_score = video_analysis&.episode_score
  def episode_tier  = video_analysis&.episode_tier

  def jd_fit_tier
    jd = video_analysis&.structured_feedback&.dig("jd_fit_score")&.to_f
    return nil unless jd
    jd >= 7.5 ? "Shortlist" : jd >= 5.0 ? "Borderline" : "Archive"
  end

  def domain_drift?
    video_analysis&.structured_feedback&.dig("domain_drift") == true
  end

  def cv_interview_gap?
    cv_fit = cv_analysis&.structured_feedback&.dig("cv_fit_score")&.to_f
    jd_fit = video_analysis&.structured_feedback&.dig("jd_fit_score")&.to_f
    return false unless cv_fit && jd_fit
    (cv_fit - jd_fit) >= 2.0
  end

  def profile_summary_lines
    cv_line   = cv_analysis&.summary.to_s.split(/\.\s+/).first&.then { |s| s.end_with?(".") ? s : "#{s}." }
    va_line   = video_analysis&.summary.to_s.split(/\.\s+/).first&.then { |s| s.end_with?(".") ? s : "#{s}." }
    rationale = video_analysis&.structured_feedback&.dig("decision_rationale")
    [cv_line, va_line, rationale].compact.select(&:present?)
  end

  def first_name
    name.to_s.split.first
  end

  def cv_feedback
    cv_analysis&.structured_feedback || {}
  end

  def video_feedback
    video_analysis&.structured_feedback || {}
  end

  # Delegates so ShortlistItem (and views) can read candidate data uniformly

  def score
    video_analysis&.score || cv_analysis&.score
  end

  def summary
    video_analysis&.summary || cv_analysis&.summary
  end

  def structured_feedback
    video_analysis&.structured_feedback || cv_analysis&.structured_feedback || {}
  end

  private

  def generate_intake_token
    self.intake_token ||= SecureRandom.urlsafe_base64(16)
  end
end
