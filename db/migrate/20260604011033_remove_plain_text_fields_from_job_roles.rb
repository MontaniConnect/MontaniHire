class RemovePlainTextFieldsFromJobRoles < ActiveRecord::Migration[8.1]
  def change
    remove_column :job_roles, :required_skills, :text
    remove_column :job_roles, :responsibilities, :text
  end
end
