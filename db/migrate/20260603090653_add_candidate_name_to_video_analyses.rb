class AddCandidateNameToVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :video_analyses, :candidate_name, :string
  end
end
