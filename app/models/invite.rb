class Invite < ApplicationRecord
  ROLES = %w[member viewer].freeze

  belongs_to :organization
  belongs_to :invited_by, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role,  inclusion: { in: ROLES }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create
  before_validation :set_expiry,     on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def expired?  = expires_at < Time.current
  def accepted? = accepted_at.present?
  def pending?  = !accepted? && !expired?

  def accept!(user)
    transaction do
      user.update!(organization: organization, role: role)
      update!(accepted_at: Time.current)
    end
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end

  def set_expiry
    self.expires_at ||= 7.days.from_now
  end
end
