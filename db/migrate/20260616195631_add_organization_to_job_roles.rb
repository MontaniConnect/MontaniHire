class AddOrganizationToJobRoles < ActiveRecord::Migration[8.1]
  def change
    add_reference :job_roles, :organization, null: true, foreign_key: true
  end
end
