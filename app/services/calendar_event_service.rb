require "net/http"
require "json"

class CalendarEventService
  class InsufficientScopeError < StandardError; end
  class PermissionDeniedError  < StandardError; end
  class CalendarNotFoundError  < StandardError; end

  def initialize(user:, slot_booking:)
    @user    = user
    @booking = slot_booking
  end

  def call
    candidate = @booking.candidate
    role      = candidate.job_role&.title || "Interview"

    description_lines = [ "Job Role: #{role}" ]
    description_lines << "Candidate Email: #{candidate.email}" if candidate.email.present?
    description_lines << "Asking Salary: #{candidate.asking_salary}" if candidate.asking_salary.present?

    attendees = [ { email: @user.email } ]
    attendees << { email: candidate.email } if candidate.email.present?

    ph_tz = ActiveSupport::TimeZone["Asia/Manila"]
    body = {
      summary:     "Preliminary Interview — #{candidate.name} (#{role})",
      description: description_lines.join("\n"),
      start:       { dateTime: @booking.starts_at.in_time_zone(ph_tz).iso8601, timeZone: "Asia/Manila" },
      end:         { dateTime: @booking.ends_at.in_time_zone(ph_tz).iso8601,   timeZone: "Asia/Manila" },
      attendees:   attendees
    }

    calendar_id = @user.interview_calendar_id.presence || "primary"
    uri = URI("https://www.googleapis.com/calendar/v3/calendars/#{ERB::Util.url_encode(calendar_id)}/events?sendUpdates=all")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.fresh_google_access_token}"
    req["Content-Type"]  = "application/json"
    req.body = JSON.generate(body)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }

    unless res.is_a?(Net::HTTPSuccess)
      data   = JSON.parse(res.body) rescue {}
      reason = data.dig("error", "details", 0, "reason")
      raise InsufficientScopeError if reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT"
      raise CalendarNotFoundError  if res.code == "404"
      raise PermissionDeniedError  if res.code == "403"
      raise "Calendar API error (#{res.code}): #{data.dig('error', 'message') || res.body}"
    end

    data = JSON.parse(res.body)
    @booking.update_columns(google_event_id: data["id"]) if data["id"]
  end
end
