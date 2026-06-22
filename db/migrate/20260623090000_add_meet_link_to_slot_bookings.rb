class AddMeetLinkToSlotBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :slot_bookings, :meet_link, :string
  end
end
