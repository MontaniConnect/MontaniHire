class ShortlistEmailService
  class << self
    def decision_url(shortlist:, selected_names:, role_name: nil)
      role    = role_name.presence || "this position"
      subject = "Interview Availability: #{role} Candidates"
      to      = [ shortlist.user&.email, ENV["OPS_EMAIL"].presence ].compact.join(",")
      body    = decision_body(shortlist, selected_names, role)
      "https://mail.google.com/mail/?view=cm&fs=1" \
        "&to=#{ERB::Util.url_encode(to)}" \
        "&su=#{ERB::Util.url_encode(subject)}" \
        "&body=#{ERB::Util.url_encode(body)}"
    end

    def shortlist_url(shortlist:, share_url:)
      subject = "Shortlist: #{shortlist.title}"
      body    = shortlist_body(shortlist, share_url)
      cc      = shortlist.client&.contact_email.presence
      url = "https://mail.google.com/mail/?view=cm&fs=1" \
        "&to=#{ERB::Util.url_encode(shortlist.client_email)}" \
        "&su=#{ERB::Util.url_encode(subject)}" \
        "&body=#{ERB::Util.url_encode(body)}"
      url += "&cc=#{ERB::Util.url_encode(cc)}" if cc
      url
    end

    private

    def decision_body(shortlist, selected_names, role_name)
      recipient = shortlist.user&.name.presence || "there"
      lines = [
        "Hi #{recipient},",
        "",
        "I've reviewed the profiles and would love to move forward with interviews for the #{role_name} position. I would like to schedule time with the following candidates:",
        ""
      ]
      selected_names.each do |name|
        lines << name
        lines << ""
      end
      lines += [
        "The dates and times I have available are below:",
        "",
        "[Date, Month Day] – [Time Range, e.g., 9:00 AM – 11:30 AM EST]",
        "",
        "[Date, Month Day] – [Time Range, e.g., 2:00 PM – 4:00 PM EST]",
        "",
        "[Date, Month Day] – [Time Range, e.g., 1:00 PM – 3:00 PM EST]",
        "",
        "Please let me know which slots work best for each of them so we can get these locked in.",
        "",
        "Best regards,"
      ]
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
end
