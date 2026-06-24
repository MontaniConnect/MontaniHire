class AddRejectionEmailSentAtToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :rejection_email_sent_at, :datetime
  end
end
