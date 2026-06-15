module Analyzable
  extend ActiveSupport::Concern

  included do
    validates :status, inclusion: { in: self::STATUSES }
    validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true

    scope :completed, -> { where(status: "completed") }
    scope :failed,    -> { where(status: "failed") }
    scope :pending,   -> { where(status: "pending") }
  end

  def transition_to!(new_status, error: nil)
    update!(status: new_status, error_message: error)
    after_transition(new_status)
  end

  def failed?    = status == "failed"
  def completed? = status == "completed"

  private

  def after_transition(_new_status)
    # hook — override in including class to react to status changes
  end
end
