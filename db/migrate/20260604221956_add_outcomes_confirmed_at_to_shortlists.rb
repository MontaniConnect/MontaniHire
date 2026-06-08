class AddOutcomesConfirmedAtToShortlists < ActiveRecord::Migration[8.1]
  def change
    add_column :shortlists, :outcomes_confirmed_at, :datetime
  end
end
