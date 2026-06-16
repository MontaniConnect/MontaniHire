class AddOrganizationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :organization, null: true, foreign_key: true
    add_column    :users, :role,        :string,  default: "member", null: false
    add_column    :users, :super_admin, :boolean, default: false,    null: false
  end
end
