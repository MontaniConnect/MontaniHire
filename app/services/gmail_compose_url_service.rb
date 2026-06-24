class GmailComposeUrlService
  class << self
    def decision_url(shortlist:, selected_names:, declined_names:)
      subject = "Final Interview Decision — #{shortlist.title}"
      to      = [ shortlist.user.email, ENV["OPS_EMAIL"].presence ].compact.join(",")
      body    = decision_body(shortlist, selected_names, declined_names)
      "https://mail.google.com/mail/?view=cm&fs=1" \
        "&to=#{ERB::Util.url_encode(to)}" \
        "&su=#{ERB::Util.url_encode(subject)}" \
        "&body=#{ERB::Util.url_encode(body)}"
    end

    def shortlist_url(shortlist:, share_url:)
      subject = "Shortlist: #{shortlist.title}"
      body = shortlist_body(shortlist, share_url)
      cc = shortlist.client&.contact_email.presence
      url = "https://mail.google.com/mail/?view=cm&fs=1" \
        "&to=#{ERB::Util.url_encode(shortlist.client_email)}" \
        "&su=#{ERB::Util.url_encode(subject)}" \
        "&body=#{ERB::Util.url_encode(body)}"
      url += "&cc=#{ERB::Util.url_encode(cc)}" if cc
      url
    end

    private

    def decision_body(shortlist, selected_names, declined_names)
      lines = [ "Hi," , "" ]

      if selected_names.any?
        lines << "Selected for final interview:"
        selected_names.each { |n| lines << "  - #{n}" }
        lines << ""
      end

      if declined_names.any?
        lines << "Declined:"
        declined_names.each { |n| lines << "  - #{n}" }
        lines << ""
      end

      if shortlist.client_availability.present?
        lines << "My availability (US timezone):"
        lines << shortlist.client_availability
        lines << ""
      end

      lines << "Best regards,"
      lines.join("\n")
    end

    def shortlist_body(shortlist, share_url)
      client_name = shortlist.client&.name.presence || "there"
      lines = [
        "Hi #{client_name},",
        "",
        "I hope you're having a great week. We are forwarding the applicants for the #{shortlist.title} for your review.",
        "",
        share_url,
        ""
      ]
      lines += [ shortlist.message, "" ] if shortlist.message.present?
      lines += [
        "Kindly let us know your feedback on the current candidates, and please feel free to reach out if you have any questions.",
        "",
        "Best regards,"
      ]
      lines.join("\n")
    end
  end

  def initialize(candidate:)
    @candidate = candidate
  end

  def invite_url(intake_url)
    role    = @candidate.job_role&.title || "this position"
    org     = @candidate.user.organization&.name.presence
    subject = [ org, role, "Preliminary Interview Invitation" ].compact.join(" — ")
    compose_url(to: @candidate.email, subject: subject, body: invite_body(role, intake_url))
  end

  def rejection_url
    role    = @candidate.job_role&.title || "this position"
    org     = @candidate.user.organization&.name.presence
    subject = [ org, role, "Application Update" ].compact.join(" — ")
    compose_url(to: @candidate.email, subject: subject, body: rejection_body(role))
  end

  def followup_url(intake_url)
    role    = @candidate.job_role&.title || "this position"
    subject = "Following up — #{role} Preliminary Interview Invitation"
    compose_url(to: @candidate.email, subject: subject, body: followup_body(role, intake_url))
  end

  private

  def compose_url(to:, subject:, body:)
    "https://mail.google.com/mail/?view=cm&fs=1" \
      "&to=#{ERB::Util.url_encode(to)}" \
      "&su=#{ERB::Util.url_encode(subject)}" \
      "&body=#{ERB::Util.url_encode(body)}"
  end

  def invite_body(role, intake_url)
    <<~TEXT
      Hi #{@candidate.first_name},

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

  def rejection_body(role)
    summary = @candidate.cv_analysis&.summary || @candidate.video_analysis&.summary
    lines = [
      "Hi #{@candidate.first_name},",
      "",
      "Thank you for taking the time to go through our process for the #{role} role. We genuinely appreciated the effort you put in.",
      "",
      "After careful review, we have decided to move forward with other candidates at this time. We know this is not the news you were hoping for, and we want to be as helpful as possible as you continue your search.",
      ""
    ]
    if summary.present?
      lines += [
        "Here is some honest feedback that we hope will be useful for your future interviews:",
        "",
        summary,
        ""
      ]
    end
    lines += [
      "We encourage you to keep applying and building on your experience. The right opportunity is out there, and this feedback is meant to help you get there faster.",
      "",
      "Thank you again for your time, and we wish you all the best.",
      "",
      "Best regards,"
    ]
    lines.join("\n")
  end

  def followup_body(role, intake_url)
    <<~TEXT
      Hi #{@candidate.first_name},

      We hope this message finds you well. We reached out a few days ago regarding the #{role} position and wanted to follow up in case our previous email didn't reach you.

      If you're still interested in proceeding, we'd love to hear from you. You can complete the short form below at your convenience:

      #{intake_url}

      Please don't hesitate to reach out if you have any questions.

      We look forward to hearing from you.

      Best regards,
    TEXT
  end
end
