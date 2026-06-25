class CandidateOutreachService
  def initialize(candidate:)
    @candidate = candidate
  end

  def invite_url(intake_url)
    role    = @candidate.job_role&.title || "this position"
    subject = "#{role} — Preliminary Interview Invitation"
    compose_url(to: @candidate.email, subject: subject, body: invite_body(role, intake_url))
  end

  def rejection_url
    role    = @candidate.job_role&.title || "this position"
    subject = "#{role} — Application Update"
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
