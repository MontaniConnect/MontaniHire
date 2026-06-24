class AddPreliminaryInterviewNoShowToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :preliminary_interview_no_show, :boolean, default: false, null: false
  end
end
