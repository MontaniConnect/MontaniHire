class AddNiceToHaveRequirementsToJobRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :job_roles, :nice_to_have_requirements, :jsonb, default: [], null: false
  end
end
