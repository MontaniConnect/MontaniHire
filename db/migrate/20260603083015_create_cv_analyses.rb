class CreateCvAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :cv_analyses do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :status, null: false, default: "pending"
      t.text    :extracted_text
      t.text    :summary
      t.jsonb   :structured_feedback, default: {}
      t.decimal :score, precision: 4, scale: 2
      t.text    :error_message

      t.timestamps
    end

    add_index :cv_analyses, :status
  end
end
