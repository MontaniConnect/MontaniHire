class CreateVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :video_analyses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :drive_file_id, null: false
      t.string :drive_file_name
      t.string :status, null: false, default: "pending"
      t.text :transcript
      t.text :summary
      t.jsonb :structured_feedback, default: {}
      t.decimal :score, precision: 4, scale: 2
      t.text :error_message
      t.string :assembly_transcript_id

      t.timestamps
    end

    add_index :video_analyses, :drive_file_id
    add_index :video_analyses, :status
    add_index :video_analyses, :assembly_transcript_id
  end
end
