module Candidates
  class CommunicationsController < BaseController
    def send_invite_email
      if @candidate.email.blank?
        redirect_to candidate_path(@candidate),
                    alert: "No email address found for #{@candidate.name}. Add one and try again."
        return
      end

      @candidate.update_columns(intake_token: SecureRandom.urlsafe_base64(16)) if @candidate.intake_token.blank?
      @candidate.update_columns(invite_sent_at: Time.current)

      intake_url = candidate_intake_url(token: @candidate.intake_token,
                                        **Rails.application.config.action_mailer.default_url_options)
      redirect_to gmail_service.invite_url(intake_url), allow_other_host: true
    end

    def send_followup_email
      if @candidate.email.blank? || @candidate.intake_token.blank?
        redirect_to candidate_path(@candidate), alert: "Cannot send follow-up — invite has not been sent yet."
        return
      end

      intake_url = candidate_intake_url(token: @candidate.intake_token,
                                        **Rails.application.config.action_mailer.default_url_options)
      redirect_to gmail_service.followup_url(intake_url), allow_other_host: true
    end

    def update_email
      email = params[:email].to_s.strip
      if email.match?(URI::MailTo::EMAIL_REGEXP)
        @candidate.update!(email: email)
        redirect_to candidate_path(@candidate), notice: "Email updated."
      else
        redirect_to candidate_path(@candidate), alert: "Invalid email address."
      end
    end

    def update_timeline
      @candidate.update!(timeline_params)
      redirect_to candidate_path(@candidate), notice: "Timeline updated."
    rescue => e
      redirect_to candidate_path(@candidate), alert: "Could not save timeline: #{e.message}"
    end

    private

    def gmail_service
      GmailComposeUrlService.new(candidate: @candidate)
    end

    def timeline_params
      params.require(:candidate).permit(:applied_at, :screened_at, :interviewed_at,
                                        :shortlisted_at, :final_interview_at, :hired_at)
    end
  end
end
