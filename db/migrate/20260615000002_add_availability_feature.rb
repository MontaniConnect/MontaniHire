class AddAvailabilityFeature < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :availability_settings, :jsonb, default: {}

    create_table :slot_bookings do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :candidate, null: false, foreign_key: true
      t.datetime   :starts_at, null: false
      t.datetime   :ends_at,   null: false
      t.string     :google_event_id
      t.timestamps
    end

    add_index :slot_bookings, [ :user_id, :starts_at ], unique: true
  end
end
