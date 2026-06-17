class AddTranscriptSegmentsToVideoAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :video_analyses, :transcript_segments, :jsonb, default: []
    add_column :video_analyses, :highlight_indices,   :jsonb, default: []
  end
end
