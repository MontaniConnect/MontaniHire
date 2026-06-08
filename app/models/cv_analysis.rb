class CvAnalysis < ApplicationRecord
  belongs_to :user
  belongs_to :job_role
  has_one_attached :cv
  has_one :candidate, foreign_key: :cv_analysis_id, dependent: :nullify
  has_many :shortlist_items, as: :shareable, dependent: :destroy

  STATUSES = %w[pending extracting analyzing completed failed].freeze

  validates :cv, presence: true
  validates :job_role, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true

  scope :completed, -> { where(status: "completed") }
  scope :failed,    -> { where(status: "failed") }

  def transition_to!(new_status, error: nil)
    update!(status: new_status, error_message: error)
  end

  def failed?    = status == "failed"
  def completed? = status == "completed"

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
end
