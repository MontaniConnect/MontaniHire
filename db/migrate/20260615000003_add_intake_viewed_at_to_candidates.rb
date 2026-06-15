class AddIntakeViewedAtToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :intake_viewed_at, :datetime
  end
end
