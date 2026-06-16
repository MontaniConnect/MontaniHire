class CreateInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :invites do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :invited_by,   null: false, foreign_key: { to_table: :users }
      t.string     :email,        null: false
      t.string     :role,         null: false, default: "viewer"
      t.string     :token,        null: false
      t.datetime   :accepted_at
      t.datetime   :expires_at,   null: false

      t.timestamps
    end

    add_index :invites, :token, unique: true
  end
end
