class JobRole < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  has_many :video_analyses, dependent: :nullify
  has_many :cv_analyses,    dependent: :nullify

  has_rich_text :required_skills
  has_rich_text :responsibilities

  EXPERIENCE_LEVELS = %w[junior mid senior executive].freeze

  validates :title, presence: true
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validates :required_skills, presence: true
  validates :responsibilities, presence: true

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
end
