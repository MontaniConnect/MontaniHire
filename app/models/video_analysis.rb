class VideoAnalysis < ApplicationRecord
  STATUSES = %w[pending transcribing analyzing awaiting_cv completed failed].freeze

  include Analyzable

  belongs_to :organization
  belongs_to :user
  belongs_to :job_role
  has_one_attached :video
  has_one :candidate, foreign_key: :video_analysis_id, dependent: :nullify
  has_many :shortlist_items, as: :shareable, dependent: :destroy

  validates :video, presence: true, unless: -> { drive_file_id.present? || transcript.present? }
  validates :job_role, presence: true

  def awaiting_cv? = status == "awaiting_cv"

  def display_name
    candidate_name.presence || (video.attached? ? video.filename.to_s : drive_file_name.presence || "Untitled")
  end

  EPISODE_WEIGHTS = {
    "relevance_discipline"  => 0.20,
    "ownership_language"    => 0.10,
    "outcome_orientation"   => 0.30,
    "adaptability_signal"   => 0.25,
    "communication_clarity" => 0.15
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
    weights = job_role&.score_weights_with_defaults&.transform_values { |v| v / 100.0 }
    EpisodeScoreCalculator.new(dimensions: dims, weights: weights).total_score
  end

  def episode_tier
    s = episode_score
    return nil unless s
    s >= 7.5 ? "Shortlist" : s >= 5.0 ? "Borderline" : "Archive"
  end
end
