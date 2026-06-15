class AddInviteSentAtToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :invite_sent_at, :datetime
  end
end
