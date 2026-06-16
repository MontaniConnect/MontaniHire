class AddFinalInterviewNoShowToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :final_interview_no_show, :boolean, default: false, null: false
  end
end
