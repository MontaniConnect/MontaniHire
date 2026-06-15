class AddIntakeFieldsToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :email,                    :string
    add_column :candidates, :intake_token,             :string
    add_column :candidates, :asking_salary,            :integer
    add_column :candidates, :intake_submitted_at,      :datetime
    add_column :candidates, :us_hours_agreement,       :boolean
    add_column :candidates, :ph_residency_confirmed,   :boolean
    add_column :candidates, :preferred_interview_time, :string
    add_index  :candidates, :intake_token, unique: true
  end
end
