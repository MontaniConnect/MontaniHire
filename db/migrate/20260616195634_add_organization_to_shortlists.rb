class AddOrganizationToShortlists < ActiveRecord::Migration[8.1]
  def change
    add_reference :shortlists, :organization, null: true, foreign_key: true
  end
end
