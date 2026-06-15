class CvAnalysis < ApplicationRecord
  STATUSES = %w[pending extracting analyzing completed failed].freeze

  include Analyzable

  belongs_to :user
  belongs_to :job_role
  has_one_attached :cv
  has_one :candidate, foreign_key: :cv_analysis_id, dependent: :nullify
  has_many :shortlist_items, as: :shareable, dependent: :destroy

  validates :cv, presence: true, unless: -> { drive_file_id.present? }
  validates :job_role, presence: true

  def display_name
    candidate_name.presence || (cv.attached? ? cv.filename.to_s : "Untitled CV")
  end

  def cv_fit_score
    structured_feedback&.dig("cv_fit_score")&.to_f
  end

  def cv_fit_tier
    s = cv_fit_score
    return nil unless s
    s >= 7.5 ? "Shortlist" : s >= 5.0 ? "Borderline" : "Archive"
  end

  private

  def after_transition(new_status)
    candidate&.update_columns(screened_at: candidate.screened_at || Time.current) if new_status == "completed"
  end
end
