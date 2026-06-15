require "net/http"
require "json"

class GmailDraftService
  class InsufficientScopeError < StandardError; end

  def initialize(user, candidate)
    @user      = user
    @candidate = candidate
  end

  def subject
    role = @candidate.job_role&.title || "this position"
    "#{role} — Preliminary Interview Invitation"
  end

  def body(intake_url)
    role  = @candidate.job_role&.title || "this position"
    first = @candidate.first_name
    <<~TEXT
      Hi #{first},

      Thank you for your interest in the #{role} position. We are pleased to inform you that you have been selected to proceed to the preliminary interview stage.

      Before we confirm your schedule, we kindly ask you to complete the short form below:

      #{intake_url}

      The form will ask you to:
      - Confirm that you are a Filipino citizen currently residing in the Philippines
      - Confirm your availability to work in US timezone
      - Share your asking salary for this role
      - Select your preferred interview time slot

      We look forward to hearing from you.

      Best regards,
    TEXT
  end

  def followup_body(intake_url)
    role  = @candidate.job_role&.title || "this position"
    first = @candidate.first_name
    <<~TEXT
      Hi #{first},

      We hope this message finds you well. We reached out a few days ago regarding the #{role} position and wanted to follow up in case our previous email didn't reach you.

      If you're still interested in proceeding, we'd love to hear from you. You can complete the short form below at your convenience:

      #{intake_url}

      Please don't hesitate to reach out if you have any questions.

      We look forward to hearing from you.

      Best regards,
    TEXT
  end

  def call
    raw = encode_message(
      to:      @candidate.email,
      subject: subject,
      body:    email_body(@candidate.job_role&.title || "this position", _intake_url)
    )
    _create_draft(raw)
  end

  def call_followup
    role = @candidate.job_role&.title || "this position"
    raw  = encode_message(
      to:      @candidate.email,
      subject: "Following up — #{role} Preliminary Interview Invitation",
      body:    followup_html_body(_intake_url)
    )
    _create_draft(raw)
  end

  private

  def _intake_url
    Rails.application.routes.url_helpers.candidate_intake_url(
      token: @candidate.intake_token,
      host:  Rails.application.config.action_mailer.default_url_options[:host]
    )
  end

  def _create_draft(raw)
    uri = URI("https://gmail.googleapis.com/gmail/v1/users/me/drafts")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.fresh_google_access_token}"
    req["Content-Type"]  = "application/json"
    req.body = JSON.generate({ message: { raw: raw } })

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    unless res.is_a?(Net::HTTPSuccess)
      body   = JSON.parse(res.body) rescue {}
      reason = body.dig("error", "details", 0, "reason")
      raise InsufficientScopeError if reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT"
      raise "Gmail API error (#{res.code}): #{body.dig('error', 'message') || res.body}"
    end
    JSON.parse(res.body)
  end

  def encode_message(to:, subject:, body:)
    message = [
      "To: #{to}",
      "Subject: #{subject}",
      "MIME-Version: 1.0",
      "Content-Type: text/html; charset=UTF-8",
      "",
      body
    ].join("\r\n")
    Base64.urlsafe_encode64(message)
  end

  def email_body(role, intake_url)
    first = @candidate.first_name
    <<~HTML
      <p>Hi #{first},</p>

      <p>Thank you for your interest in the <strong>#{role}</strong> position. We are pleased to inform you that you have been selected to proceed to the preliminary interview stage.</p>

      <p>Before we confirm your schedule, we kindly ask you to complete the short form below:</p>

      <p><a href="#{intake_url}" style="color:#2563eb;">#{intake_url}</a></p>

      <p>The form will ask you to:
        <ul>
          <li>Confirm that you are a Filipino citizen currently residing in the Philippines</li>
          <li>Confirm your availability to work in US timezone</li>
          <li>Share your asking salary for this role</li>
          <li>Select your preferred interview time slot</li>
        </ul>
      </p>

      <p>We look forward to hearing from you.</p>

      <p>Best regards,</p>
    HTML
  end

  def followup_html_body(intake_url)
    role  = @candidate.job_role&.title || "this position"
    first = @candidate.first_name
    <<~HTML
      <p>Hi #{first},</p>

      <p>We hope this message finds you well. We reached out a few days ago regarding the <strong>#{role}</strong> position and wanted to follow up in case our previous email didn't reach you.</p>

      <p>If you're still interested in proceeding, we'd love to hear from you. You can complete the short form below at your convenience:</p>

      <p><a href="#{intake_url}" style="color:#2563eb;">#{intake_url}</a></p>

      <p>Please don't hesitate to reach out if you have any questions.</p>

      <p>We look forward to hearing from you.</p>

      <p>Best regards,</p>
    HTML
  end
end
