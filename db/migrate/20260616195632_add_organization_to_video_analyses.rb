class AddOrganizationToVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_reference :video_analyses, :organization, null: true, foreign_key: true
  end
end
