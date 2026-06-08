class CreateShortlistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :shortlist_items do |t|
      t.references :shortlist,  null: false, foreign_key: true
      t.references :shareable,  null: false, polymorphic: true
      t.string :client_status,  default: "pending"
      t.text   :client_comment

      t.timestamps
    end

    add_index :shortlist_items, %i[shortlist_id shareable_type shareable_id], unique: true,
              name: "index_shortlist_items_on_shortlist_and_shareable"
  end
end
