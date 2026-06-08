class CreateShortlists < ActiveRecord::Migration[8.1]
  def change
    create_table :shortlists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title,        null: false
      t.string :client_email, null: false
      t.string :token,        null: false
      t.text   :message

      t.timestamps
    end

    add_index :shortlists, :token, unique: true
  end
end
