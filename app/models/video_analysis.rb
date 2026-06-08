class VideoAnalysis < ApplicationRecord
  belongs_to :user
  belongs_to :job_role
  has_one_attached :video
  has_one :candidate, foreign_key: :video_analysis_id, dependent: :nullify
  has_many :shortlist_items, as: :shareable, dependent: :destroy

  STATUSES = %w[pending transcribing analyzing awaiting_cv completed failed].freeze

  validates :video, presence: true
  validates :job_role, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true

  scope :pending,   -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :failed,    -> { where(status: "failed") }

  def transition_to!(new_status, error: nil)
    update!(status: new_status, error_message: error)
  end

  def failed?      = status == "failed"
  def completed?   = status == "completed"
  def awaiting_cv? = status == "awaiting_cv"

  def display_name
    candidate_name.presence || (video.attached? ? video.filename.to_s : drive_file_name.presence || "Untitled")
  end

  EPISODE_WEIGHTS = {
    "relevance_discipline"  => 0.20,
    "ownership_language"    => 0.20,
    "outcome_orientation"   => 0.20,
    "adaptability_signal"   => 0.20,
    "communication_clarity" => 0.20
  }.freeze

  EPISODE_LEVEL_VALUES = {
    "relevance_discipline"  => { "meets" => 1.0, "partially_meets" => 0.7, "vague" => 0.4, "does_not_meet" => 0.0 },
    "ownership_language"    => { "meets" => 1.0, "partially_meets" => 0.7, "vague" => 0.4, "does_not_meet" => 0.0 },
    "outcome_orientation"   => { "meets" => 1.0, "partially_meets" => 0.7, "vague" => 0.4, "does_not_meet" => 0.0 },
    "adaptability_signal"   => { "meets" => 1.0, "partially_meets" => 0.7, "vague" => 0.4, "does_not_meet" => 0.0 },
    "communication_clarity" => { "meets" => 1.0, "partially_meets" => 0.7, "vague" => 0.4, "does_not_meet" => 0.0 }
  }.freeze

  def episode_score
    dims = structured_feedback&.dig("episode_dimensions")
    return nil unless dims.present?
    total_weight = 0.0
    total_score  = 0.0
    EPISODE_WEIGHTS.each do |dim, weight|
      level = dims[dim]
      next unless level.present?
      value = EPISODE_LEVEL_VALUES.dig(dim, level)
      next unless value
      total_score  += value * weight
      total_weight += weight
    end
    return nil if total_weight.zero?
    (total_score / total_weight * 10).round(1)
  end

  def episode_tier
    s = episode_score
    return nil unless s
    s >= 7.5 ? "Shortlist" : s >= 5.0 ? "Borderline" : "Archive"
  end
end
