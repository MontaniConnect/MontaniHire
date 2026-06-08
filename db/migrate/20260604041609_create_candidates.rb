class CreateCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :candidates do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :job_role,     null: true,  foreign_key: true
      t.bigint     :cv_analysis_id
      t.bigint     :video_analysis_id
      t.string     :name,           null: false
      t.string     :pipeline_stage, null: false, default: "cv_review"
      t.timestamps
    end

    add_index :candidates, :cv_analysis_id
    add_index :candidates, :video_analysis_id
  end
end
