class User < ApplicationRecord
  class GoogleTokenRevoked < StandardError; end

  belongs_to :organization, optional: true

  ROLES = %w[owner member viewer super_admin].freeze
  validates :role, inclusion: { in: ROLES }

  def owner?       = role == "owner"
  def member?      = role == "member"
  def viewer?      = role == "viewer"
  def super_admin? = role == "super_admin"
  def can_write?   = owner? || member?

  has_many :job_roles,      dependent: :nullify
  has_many :shortlists,     dependent: :nullify
  has_many :video_analyses, dependent: :nullify
  has_many :cv_analyses,    dependent: :nullify
  has_many :candidates,     dependent: :nullify
  has_many :slot_bookings,  dependent: :destroy

  DAY_NAMES = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

  DEFAULT_AVAILABILITY = {
    "slot_duration" => 30,
    "timezone"      => "Asia/Manila",
    "days"          => {
      "monday"    => { "enabled" => true,  "start" => "09:00", "end" => "17:00" },
      "tuesday"   => { "enabled" => true,  "start" => "09:00", "end" => "17:00" },
      "wednesday" => { "enabled" => true,  "start" => "09:00", "end" => "17:00" },
      "thursday"  => { "enabled" => true,  "start" => "09:00", "end" => "17:00" },
      "friday"    => { "enabled" => true,  "start" => "09:00", "end" => "17:00" },
      "saturday"  => { "enabled" => false, "start" => "09:00", "end" => "17:00" },
      "sunday"    => { "enabled" => false, "start" => "09:00", "end" => "17:00" }
    }
  }.freeze

  def availability
    DEFAULT_AVAILABILITY.deep_merge(availability_settings || {})
  end

  def available_slots(days_ahead: 28)
    config   = availability
    tz       = ActiveSupport::TimeZone[config["timezone"]] || Time.zone
    duration = config["slot_duration"].to_i.minutes
    now      = tz.now

    booked_times = slot_bookings
      .where(starts_at: now...(now + days_ahead.days))
      .pluck(:starts_at)
      .map { |t| t.in_time_zone(tz) }

    slots = []
    (0...days_ahead).each do |offset|
      date     = (now + offset.days).to_date
      day_name = DAY_NAMES[date.wday]
      day_cfg  = config.dig("days", day_name)
      next unless day_cfg&.fetch("enabled", false)

      slot_start = tz.parse("#{date} #{day_cfg['start']}")
      slot_end   = tz.parse("#{date} #{day_cfg['end']}")
      next if slot_end <= now

      current = slot_start < now ? slot_start + ((now - slot_start) / duration).ceil * duration : slot_start
      while current + duration <= slot_end
        slots << current unless booked_times.include?(current)
        current += duration
      end
    end

    slots
  end

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def google_connected?
    google_refresh_token.present?
  end

  def google_token_fresh?
    google_token_expires_at.present? && google_token_expires_at > 5.minutes.from_now
  end

  # Returns a valid access token, refreshing if expired.
  def fresh_google_access_token
    return nil unless google_refresh_token.present?
    refresh_google_token! unless google_token_fresh?
    google_access_token
  end

  private

  def refresh_google_token!
    require "net/http"
    uri  = URI("https://oauth2.googleapis.com/token")
    body = {
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
      refresh_token: google_refresh_token,
      grant_type:    "refresh_token"
    }
    response = Net::HTTP.post_form(uri, body)
    data     = JSON.parse(response.body)
    if data["error"].present?
      raise GoogleTokenRevoked,
        "Google token refresh failed (#{data['error']}): #{data['error_description'] || 'no details'}"
    end

    update_columns(
      google_access_token:     data["access_token"],
      google_token_expires_at: data["expires_in"] ? Time.current + data["expires_in"].to_i.seconds : nil
    )
  end
end
