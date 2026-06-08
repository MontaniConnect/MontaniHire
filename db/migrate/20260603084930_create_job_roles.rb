class CreateJobRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :job_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :experience_level, null: false, default: "mid"
      t.text   :required_skills
      t.text   :responsibilities
      t.text   :description

      t.timestamps
    end
  end
end
