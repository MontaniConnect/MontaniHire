class AddCandidateNameToCvAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :cv_analyses, :candidate_name, :string
  end
end
