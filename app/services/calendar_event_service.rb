require "net/http"
require "json"

class CalendarEventService
  class InsufficientScopeError < StandardError; end

  def initialize(user:, slot_booking:)
    @user    = user
    @booking = slot_booking
  end

  def call
    candidate = @booking.candidate
    role      = candidate.job_role&.title || "Interview"

    ph_tz = ActiveSupport::TimeZone["Asia/Manila"]
    body = {
      summary:   "Preliminary Interview — #{candidate.name} (#{role})",
      start:     { dateTime: @booking.starts_at.in_time_zone(ph_tz).iso8601, timeZone: "Asia/Manila" },
      end:       { dateTime: @booking.ends_at.in_time_zone(ph_tz).iso8601,   timeZone: "Asia/Manila" },
      attendees: candidate.email.present? ? [{ email: candidate.email }] : []
    }

    uri = URI("https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=all")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.fresh_google_access_token}"
    req["Content-Type"]  = "application/json"
    req.body = JSON.generate(body)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }

    unless res.is_a?(Net::HTTPSuccess)
      data   = JSON.parse(res.body) rescue {}
      reason = data.dig("error", "details", 0, "reason")
      raise InsufficientScopeError if reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT"
      raise "Calendar API error (#{res.code}): #{data.dig('error', 'message') || res.body}"
    end

    data = JSON.parse(res.body)
    @booking.update_columns(google_event_id: data["id"]) if data["id"]
  end
end
