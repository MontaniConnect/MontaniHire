class SlotBooking < ApplicationRecord
  belongs_to :user
  belongs_to :candidate

  validates :starts_at, :ends_at, presence: true
  validates :starts_at, uniqueness: { scope: :user_id }
end
