class AddPromptVersionToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :video_analyses, :prompt_version, :string
    add_column :cv_analyses,    :prompt_version, :string
  end
end
