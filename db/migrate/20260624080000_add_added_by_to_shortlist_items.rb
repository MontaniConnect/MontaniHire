class AddAddedByToShortlistItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :shortlist_items, :added_by, foreign_key: { to_table: :users }, null: true
  end
end
