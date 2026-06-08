class AddCleanedTranscriptToVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :video_analyses, :cleaned_transcript, :text
  end
end
