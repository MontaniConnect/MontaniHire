class Organization < ApplicationRecord
  has_many :users,          dependent: :nullify
  has_many :candidates,     dependent: :destroy
  has_many :job_roles,      dependent: :destroy
  has_many :video_analyses, dependent: :destroy
  has_many :cv_analyses,    dependent: :destroy
  has_many :shortlists,     dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9-]+\z/, message: "only lowercase letters, numbers, and hyphens" }

  before_validation :generate_slug, on: :create

  private

  def generate_slug
    return if slug.present?
    base  = name.to_s.parameterize
    slug  = base.presence || "org"
    taken = self.class.where("slug LIKE ?", "#{slug}%").pluck(:slug).to_set
    if taken.include?(slug)
      i = 2
      i += 1 while taken.include?("#{slug}-#{i}")
      slug = "#{slug}-#{i}"
    end
    self.slug = slug
  end
end
