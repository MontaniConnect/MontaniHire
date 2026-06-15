class AddTimelineDatesToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :applied_at,        :datetime
    add_column :candidates, :screened_at,        :datetime
    add_column :candidates, :interviewed_at,     :datetime
    add_column :candidates, :shortlisted_at,     :datetime
    add_column :candidates, :final_interview_at, :datetime

    # Backfill applied_at from created_at for existing records
    reversible do |dir|
      dir.up { execute "UPDATE candidates SET applied_at = created_at WHERE applied_at IS NULL" }
    end
  end
end
