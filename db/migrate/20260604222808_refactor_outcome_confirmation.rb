class RefactorOutcomeConfirmation < ActiveRecord::Migration[8.1]
  def change
    remove_column :shortlists, :outcomes_confirmed_at, :datetime
    add_column    :candidates, :outcome_confirmed_at, :datetime
  end
end
