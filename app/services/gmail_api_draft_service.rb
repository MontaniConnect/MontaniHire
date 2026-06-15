require "net/http"
require "json"

class GmailApiDraftService
  class InsufficientScopeError < StandardError; end

  def initialize(user:, candidate:)
    @user      = user
    @candidate = candidate
  end

  def invite_url(intake_url)
    role = @candidate.job_role&.title || "this position"
    create_draft(
      to:      @candidate.email,
      subject: "#{role} — Preliminary Interview Invitation",
      body:    invite_html(role, intake_url)
    )
    "https://mail.google.com/mail/#drafts"
  end

  def followup_url(intake_url)
    role = @candidate.job_role&.title || "this position"
    create_draft(
      to:      @candidate.email,
      subject: "Following up — #{role} Preliminary Interview Invitation",
      body:    followup_html(role, intake_url)
    )
    "https://mail.google.com/mail/#drafts"
  end

  private

  def create_draft(to:, subject:, body:)
    raw = encode_message(to: to, subject: subject, body: body)
    uri = URI("https://gmail.googleapis.com/gmail/v1/users/me/drafts")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@user.fresh_google_access_token}"
    req["Content-Type"]  = "application/json"
    req.body = JSON.generate({ message: { raw: raw } })

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    unless res.is_a?(Net::HTTPSuccess)
      data   = JSON.parse(res.body) rescue {}
      reason = data.dig("error", "details", 0, "reason")
      raise InsufficientScopeError if reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT"
      raise "Gmail API error (#{res.code}): #{data.dig('error', 'message') || res.body}"
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

  def invite_html(role, intake_url)
    <<~HTML
      <p>Hi #{@candidate.first_name},</p>
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

  def followup_html(role, intake_url)
    <<~HTML
      <p>Hi #{@candidate.first_name},</p>
      <p>We hope this message finds you well. We reached out a few days ago regarding the <strong>#{role}</strong> position and wanted to follow up in case our previous email didn't reach you.</p>
      <p>If you're still interested in proceeding, we'd love to hear from you. You can complete the short form below at your convenience:</p>
      <p><a href="#{intake_url}" style="color:#2563eb;">#{intake_url}</a></p>
      <p>Please don't hesitate to reach out if you have any questions.</p>
      <p>We look forward to hearing from you.</p>
      <p>Best regards,</p>
    HTML
  end
end
