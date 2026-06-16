class AddDriveVideoFileIdToVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :video_analyses, :drive_video_file_id, :string
  end
end
