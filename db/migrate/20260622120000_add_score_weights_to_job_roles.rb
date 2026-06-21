class AddScoreWeightsToJobRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :job_roles, :score_weights, :jsonb, default: {}
  end
end
