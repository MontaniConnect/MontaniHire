class CandidatesController < ApplicationController
  before_action :set_candidate, only: %i[show update advance reject revert final_interview not_invited hire offer_declined not_selected confirm_outcome toggle_no_show update_timeline destroy send_invite_email send_followup_email update_email]

  def index
    @q           = params[:q].to_s.strip
    @job_role_id = params[:job_role_id].presence

    @job_roles = JobRole.where(id: current_user.candidates.where.not(job_role_id: nil).select(:job_role_id))
                        .order(:title)

    scope = current_user.candidates.includes(:job_role, :cv_analysis, :video_analysis)
                        .order(created_at: :desc)

    if @q.present?
      scope = scope.where(
        "candidates.name ILIKE :q OR job_roles.title ILIKE :q",
        q: "%#{@q}%"
      ).references(:job_role)
    end

    if @job_role_id
      scope = scope.where(job_role_id: @job_role_id)
    end

    @candidates = scope
  end

  def show
    @shortlist_item = ShortlistItem.joins(:shortlist)
                                   .where(shortlists: { user_id: current_user.id })
                                   .find_by(candidate_id: @candidate.id)
    @candidate.update_columns(intake_viewed_at: Time.current) if @candidate.intake_unread?
  end

  def update
    new_role = current_user.job_roles.find_by(id: params[:candidate][:job_role_id])
    if new_role
      @candidate.update!(job_role: new_role)
      @candidate.cv_analysis&.update!(job_role: new_role)
      @candidate.video_analysis&.update!(job_role: new_role)
      redirect_to candidate_path(@candidate), notice: "Job role updated to \"#{new_role.title}\"."
    else
      redirect_to candidate_path(@candidate), alert: "Invalid job role."
    end
  end

  def advance
    @candidate.advance_to_interview!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} advanced to preliminary interview."
  end

  def reject
    @candidate.reject!
    redirect_back fallback_location: candidates_path,
                  notice: "#{@candidate.name} marked as rejected."
  end

  def revert
    was_shortlisted = @candidate.pipeline_stage == "client_interview"
    @candidate.revert!
    notice = was_shortlisted \
      ? "#{@candidate.name} moved back to Preliminary Interview and removed from all shortlists."
      : "#{@candidate.name} reverted to CV Review."
    redirect_to candidate_path(@candidate), notice: notice
  end

  def final_interview
    @candidate.advance_to_final_interview!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} confirmed for final interview."
  end

  def not_invited
    @candidate.mark_not_invited!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} marked as not invited."
  end

  def hire
    @candidate.hire!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} marked as hired."
  end

  def offer_declined
    @candidate.mark_offer_declined!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} marked as offer declined."
  end

  def not_selected
    @candidate.mark_not_selected!
    redirect_to candidate_path(@candidate),
                notice: "#{@candidate.name} marked as not selected."
  end

  def confirm_outcome
    if @candidate.outcome_confirmed?
      @candidate.update!(outcome_confirmed_at: nil, outcome_note: nil)
      redirect_back fallback_location: candidate_path(@candidate),
                    notice: "Outcome confirmation removed for #{@candidate.name}."
    else
      note = params[:outcome_note].to_s.strip.presence
      @candidate.update!(outcome_confirmed_at: Time.current, outcome_note: note)
      redirect_back fallback_location: candidate_path(@candidate),
                    notice: "Outcome confirmed for #{@candidate.name}. This will calibrate future analyses."
    end
  end

  def update_timeline
    @candidate.update!(timeline_params)
    redirect_to candidate_path(@candidate), notice: "Timeline updated."
  rescue => e
    redirect_to candidate_path(@candidate), alert: "Could not save timeline: #{e.message}"
  end

  def toggle_no_show
    if @candidate.no_show?
      @candidate.undo_no_show!
      redirect_to candidate_path(@candidate), notice: "No-show cleared for #{@candidate.name}."
    else
      @candidate.no_show!
      redirect_to candidate_path(@candidate), notice: "#{@candidate.name} marked as no-show."
    end
  end

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
    role       = @candidate.job_role&.title || "this position"
    subject    = ERB::Util.url_encode("#{role} — Preliminary Interview Invitation")
    body       = ERB::Util.url_encode(GmailDraftService.new(nil, @candidate).body(intake_url))
    redirect_to "https://mail.google.com/mail/?view=cm&fs=1&to=#{ERB::Util.url_encode(@candidate.email)}&su=#{subject}&body=#{body}",
                allow_other_host: true
  end

  def send_followup_email
    if @candidate.email.blank? || @candidate.intake_token.blank?
      redirect_to candidate_path(@candidate), alert: "Cannot send follow-up — invite has not been sent yet."
      return
    end

    intake_url = candidate_intake_url(token: @candidate.intake_token,
                                      **Rails.application.config.action_mailer.default_url_options)
    role       = @candidate.job_role&.title || "this position"
    subject    = ERB::Util.url_encode("Following up — #{role} Preliminary Interview Invitation")
    body       = ERB::Util.url_encode(GmailDraftService.new(nil, @candidate).followup_body(intake_url))
    redirect_to "https://mail.google.com/mail/?view=cm&fs=1&to=#{ERB::Util.url_encode(@candidate.email)}&su=#{subject}&body=#{body}",
                allow_other_host: true
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

  def destroy
    name = @candidate.name
    @candidate.cv_analysis&.destroy
    @candidate.video_analysis&.destroy
    @candidate.destroy
    redirect_to candidates_path, notice: "#{name} has been deleted."
  end

  private

  def timeline_params
    params.require(:candidate).permit(:applied_at, :screened_at, :interviewed_at,
                                      :shortlisted_at, :final_interview_at, :hired_at)
  end

  def set_candidate
    @candidate = current_user.candidates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to candidates_path, alert: "Candidate not found."
  end
end
