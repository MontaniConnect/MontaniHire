class AddRecruiterNotesToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :recruiter_notes, :text
  end
end
