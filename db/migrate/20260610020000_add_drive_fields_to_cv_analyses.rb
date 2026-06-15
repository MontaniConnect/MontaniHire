class AddDriveFieldsToCvAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :cv_analyses, :drive_file_id,   :string
    add_column :cv_analyses, :drive_file_name,  :string
    add_index  :cv_analyses, :drive_file_id
  end
end
