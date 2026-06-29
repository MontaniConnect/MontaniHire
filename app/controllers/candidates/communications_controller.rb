module Candidates
  class CommunicationsController < BaseController
    before_action :check_invites_enabled, only: [ :send_invite_email, :send_followup_email ]

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

    def send_rejection_email
      if @candidate.email.blank?
        redirect_to candidates_path,
                    alert: "No email address on file for #{@candidate.name}."
        return
      end

      redirect_to gmail_service.rejection_url, allow_other_host: true
    end

    def mark_rejection_sent
      @candidate.update_columns(rejection_email_sent_at: Time.current)
      redirect_to candidates_path, notice: "Rejection email marked as sent for #{@candidate.name}."
    end

    def update_name
      name = params[:name].to_s.strip
      if name.present?
        @candidate.update!(name: name)
        redirect_to candidate_path(@candidate), notice: "Name updated."
      else
        redirect_to candidate_path(@candidate), alert: "Name can't be blank."
      end
    end

    def update_recruiter_notes
      @candidate.update!(recruiter_notes: params[:recruiter_notes].to_s.strip.presence)
      redirect_to candidate_path(@candidate), notice: "Notes saved."
    end

    def update_compensation_package
      @candidate.update!(compensation_package: params[:compensation_package].to_s.strip.presence)
      redirect_to candidate_path(@candidate), notice: "Compensation package saved."
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

    def sync_calendar
      booking = @candidate.slot_booking
      unless booking
        redirect_to candidate_path(@candidate), alert: "No slot booking found for #{@candidate.name}."
        return
      end

      unless current_user.google_connected?
        redirect_to candidate_path(@candidate),
                    alert: "Connect your Google account in Settings before syncing to Calendar."
        return
      end

      CalendarEventService.new(user: current_user, slot_booking: booking).call
      redirect_to candidate_path(@candidate), notice: "Interview added to your Google Calendar."
    rescue User::GoogleTokenRevoked
      redirect_to settings_path,
                  alert: "Your Google account needs to be reconnected. Go to Settings and reconnect it, then try again."
    rescue CalendarEventService::InsufficientScopeError
      redirect_to candidate_path(@candidate),
                  alert: "Calendar permission missing. Disconnect and reconnect your Google account in Settings, then try again."
    rescue CalendarEventService::PermissionDeniedError
      redirect_to settings_path,
                  alert: "You don't have write access to the calendar saved in Settings. Check that you've been granted edit access, or clear the Calendar ID to use your primary calendar."
    rescue CalendarEventService::CalendarNotFoundError
      redirect_to settings_path,
                  alert: "Calendar ID not found. Verify the ID in Settings or leave it blank to use your primary calendar."
    rescue => e
      Rails.logger.error "#{self.class}: #{e.class}: #{e.message.truncate(200)}"
      redirect_to candidate_path(@candidate), alert: "Could not sync calendar: #{e.message.truncate(200)}"
    end

    private

    def check_invites_enabled
      unless Rails.application.config.x.invites_enabled
        redirect_to candidate_path(@candidate), notice: "Email invites are currently paused." and return
      end
    end

    def gmail_service
      CandidateOutreachService.new(candidate: @candidate)
    end

    def timeline_params
      params.require(:candidate).permit(:applied_at, :screened_at, :interviewed_at,
                                        :shortlisted_at, :final_interview_at, :hired_at)
    end
  end
end
