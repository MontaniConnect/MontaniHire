class AddOrganizationToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_reference :candidates, :organization, null: true, foreign_key: true
  end
end
