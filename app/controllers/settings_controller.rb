class SettingsController < AuthenticatedController
  DAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

  def show
    @availability = current_user.availability
    @upcoming_bookings = current_user.slot_bookings
                                     .includes(:candidate)
                                     .where("starts_at >= ?", Time.current)
                                     .order(:starts_at)
    if current_user.owner?
      @members = current_organization.users.order(:name, :email)
      @pending_invites = current_organization.invites.pending.includes(:invited_by).order(created_at: :desc)
    end
  end

  before_action :require_write_access!, only: [:update_availability]

  def update_availability
    days = {}
    DAYS.each do |day|
      days[day] = {
        "enabled" => params.dig(:days, day, :enabled) == "1",
        "start"   => params.dig(:days, day, :start).presence || "09:00",
        "end"     => params.dig(:days, day, :end).presence || "17:00"
      }
    end

    current_user.update!(availability_settings: {
      "slot_duration" => params[:slot_duration].to_i.clamp(15, 120),
      "timezone"      => params[:timezone].presence || "Asia/Manila",
      "days"          => days
    })

    redirect_to settings_path, notice: "Availability saved."
  end
end
