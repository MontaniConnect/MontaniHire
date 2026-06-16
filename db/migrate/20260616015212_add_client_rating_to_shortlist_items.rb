class AddClientRatingToShortlistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :shortlist_items, :client_rating, :integer
  end
end
