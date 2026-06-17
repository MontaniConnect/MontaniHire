class Shortlist < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :client, optional: true
  has_many :shortlist_items, dependent: :destroy

  validates :title, presence: true
  validates :client_email, presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  # client_logo_url validator removed — field is legacy (Migration B will drop it).
  # Logo URL validation now lives on Client.

  before_validation :generate_token, on: :create

  def verified_by?(email)
    client_email.downcase.strip == email.to_s.downcase.strip
  end


def share_url
    Rails.application.routes.url_helpers.shared_shortlist_url(token)
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end
end
