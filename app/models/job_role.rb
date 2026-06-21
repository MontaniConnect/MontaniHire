class JobRole < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :client, optional: true
  has_many :video_analyses, dependent: :nullify
  has_many :cv_analyses,    dependent: :nullify

  has_rich_text :required_skills
  has_rich_text :responsibilities

  EXPERIENCE_LEVELS = %w[junior mid senior executive].freeze

  DIMENSION_KEYS = %w[
    relevance_discipline ownership_language outcome_orientation
    adaptability_signal communication_clarity
  ].freeze

  DEFAULT_SCORE_WEIGHTS = VideoAnalysis::EPISODE_WEIGHTS.transform_values { |v| (v * 100).round }.freeze

  validates :title, presence: true
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validates :required_skills, presence: true
  validates :responsibilities, presence: true
  validate  :score_weights_sum_to_100

  def score_weights_with_defaults
    return DEFAULT_SCORE_WEIGHTS if score_weights.blank?
    DEFAULT_SCORE_WEIGHTS.merge(score_weights.transform_keys(&:to_s).transform_values(&:to_i))
  end

  def requirements_locked?
    must_have_requirements.present?
  end

  def to_prompt
    lines = []
    lines << "Job Role: #{title}"
    lines << "Experience Level: #{experience_level.capitalize}"

    if requirements_locked?
      lines << "Must-Have Requirements (score cv_requirements_coverage / jd_requirements_coverage against these exactly — do not add, remove, or reword any requirement):\n" +
               must_have_requirements.each_with_index.map { |r, i| "  #{i + 1}. #{r}" }.join("\n")
    end

    if nice_to_have_requirements.present?
      lines << "Nice-to-Have Requirements (score nice_to_have_requirements_coverage against these exactly — same order, same wording):\n" +
               nice_to_have_requirements.each_with_index.map { |r, i| "  #{i + 1}. #{r}" }.join("\n")
    end

    lines << "Required Skills:\n#{required_skills.to_plain_text}" if required_skills.present?
    lines << "Responsibilities:\n#{responsibilities.to_plain_text}" if responsibilities.present?
    lines << "Additional Context: #{description}" if description.present?

    lines.join("\n\n")
  end

  private

  def score_weights_sum_to_100
    return if score_weights.blank?
    missing = DIMENSION_KEYS - score_weights.keys.map(&:to_s)
    if missing.any?
      errors.add(:score_weights, "must include all 5 dimensions (missing: #{missing.join(', ')})")
      return
    end
    total = score_weights.values.sum(&:to_i)
    errors.add(:score_weights, "must sum to 100 (got #{total})") unless total == 100
  end
end
