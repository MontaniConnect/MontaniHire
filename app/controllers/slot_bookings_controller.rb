class SlotBookingsController < AuthenticatedController
  before_action :set_slot_booking
  before_action :require_write_access!

  def update_meet_link
    @slot_booking.update!(meet_link: params[:meet_link].to_s.strip.presence)
    redirect_to candidates_path, notice: "Meet link updated."
  end

  private

  def set_slot_booking
    candidate = current_organization.candidates.joins(:slot_booking)
                                    .find_by!(slot_bookings: { id: params[:id] })
    @slot_booking = candidate.slot_booking
  end
end
