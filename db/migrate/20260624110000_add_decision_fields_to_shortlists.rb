class AddDecisionFieldsToShortlists < ActiveRecord::Migration[8.0]
  def change
    add_column :shortlists, :client_availability, :text
    add_column :shortlists, :client_decision_submitted_at, :datetime
  end
end
