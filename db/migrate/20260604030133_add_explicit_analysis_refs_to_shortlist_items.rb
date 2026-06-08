class AddExplicitAnalysisRefsToShortlistItems < ActiveRecord::Migration[8.1]
  def up
    add_column :shortlist_items, :cv_analysis_id,    :bigint
    add_column :shortlist_items, :video_analysis_id, :bigint
    add_index  :shortlist_items, :cv_analysis_id
    add_index  :shortlist_items, :video_analysis_id

    # Backfill from the existing polymorphic columns
    execute <<-SQL
      UPDATE shortlist_items SET video_analysis_id = shareable_id
        WHERE shareable_type = 'VideoAnalysis';
      UPDATE shortlist_items SET cv_analysis_id = shareable_id
        WHERE shareable_type = 'CvAnalysis';
    SQL
  end

  def down
    remove_index  :shortlist_items, :video_analysis_id
    remove_index  :shortlist_items, :cv_analysis_id
    remove_column :shortlist_items, :video_analysis_id
    remove_column :shortlist_items, :cv_analysis_id
  end
end
