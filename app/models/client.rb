class Client < ApplicationRecord
  include ValidatesLogoUrl

  belongs_to :organization
  has_many :job_roles,  dependent: :nullify
  has_many :shortlists, dependent: :nullify

  validates :name, presence: true
  validates :contact_email,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_blank: true
end
