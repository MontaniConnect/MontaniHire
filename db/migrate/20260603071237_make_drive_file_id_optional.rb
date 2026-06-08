class MakeDriveFileIdOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :video_analyses, :drive_file_id, true
  end
end
