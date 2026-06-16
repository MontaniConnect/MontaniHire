class AddOrganizationToCvAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_reference :cv_analyses, :organization, null: true, foreign_key: true
  end
end
