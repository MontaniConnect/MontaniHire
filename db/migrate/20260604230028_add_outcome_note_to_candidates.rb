class AddOutcomeNoteToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :outcome_note, :text
  end
end
