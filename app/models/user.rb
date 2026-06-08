class User < ApplicationRecord
  has_many :job_roles,      dependent: :destroy
  has_many :shortlists,     dependent: :destroy
  has_many :video_analyses, dependent: :destroy
  has_many :cv_analyses,    dependent: :destroy
  has_many :candidates,     dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
