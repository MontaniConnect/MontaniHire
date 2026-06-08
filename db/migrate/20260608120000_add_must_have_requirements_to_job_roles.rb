class AddMustHaveRequirementsToJobRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :job_roles, :must_have_requirements, :jsonb, default: [], null: false
  end
end
