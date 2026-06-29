class IntakeController < ApplicationController
  layout "intake"

  def show
    @candidate = Candidate.find_by(intake_token: params[:token])
    return render plain: "This link is invalid.", status: :not_found unless @candidate
    load_slots
  end

  def submit
    @candidate = Candidate.find_by(intake_token: params[:token])
    return render plain: "This link is invalid.", status: :not_found unless @candidate

    if @candidate.intake_submitted?
      load_slots
      render :show
      return
    end

    slot_starts_at = params[:slot_starts_at].presence && Time.parse(params[:slot_starts_at]) rescue nil

    booking = nil
    if slot_starts_at
      config    = @candidate.user.availability
      duration  = config["slot_duration"].to_i.minutes
      slot_ends = slot_starts_at + duration

      booking = @candidate.user.slot_bookings.build(
        candidate:  @candidate,
        starts_at:  slot_starts_at,
        ends_at:    slot_ends
      )

      unless booking.save
        load_slots
        @error = "That slot is no longer available. Please choose another."
        render :show
        return
      end
    end

    @candidate.update!(
      us_hours_agreement:       params[:us_hours_agreement] == "1",
      ph_residency_confirmed:   params[:ph_residency_confirmed] == "1",
      asking_salary:            params[:asking_salary].presence,
      preferred_interview_time: slot_starts_at&.strftime("%-I:%M %p %Z"),
      job_source:               params[:job_source].presence,
      job_source_other:         params[:job_source] == "others" ? params[:job_source_other].presence : nil,
      intake_submitted_at:      Time.current
    )

    if booking && @candidate.user.google_connected?
      begin
        CalendarEventService.new(user: @candidate.user, slot_booking: booking).call
      rescue => e
        Rails.logger.error "#{self.class}: #{e.class}: #{e.message.truncate(200)}"
      end
    end
  end

  private

  def load_slots
    user   = @candidate.user
    tz     = ActiveSupport::TimeZone[user.availability["timezone"]] || Time.zone
    @timezone_label = tz.to_s.gsub(/\(.*?\)\s*/, "").strip
    @slots = user.available_slots.group_by { |s| s.in_time_zone(tz).to_date }.first(5).to_h
  end
end
