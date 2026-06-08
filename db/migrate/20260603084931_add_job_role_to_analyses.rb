class AddJobRoleToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_reference :video_analyses, :job_role, null: true, foreign_key: true
    add_reference :cv_analyses,    :job_role, null: true, foreign_key: true
  end
end
