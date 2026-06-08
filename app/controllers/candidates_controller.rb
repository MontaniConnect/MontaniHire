class CandidatesController < ApplicationController
  before_action :set_candidate, only: %i[show update advance reject revert final_interview not_invited hire offer_declined not_selected confirm_outcome toggle_no_show destroy]

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
    redirect_to new_video_analysis_path(candidate_id: @candidate.id),
                notice: "#{@candidate.name} advanced to preliminary interview. Upload their interview video below."
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

  def toggle_no_show
    if @candidate.no_show?
      @candidate.undo_no_show!
      redirect_to candidate_path(@candidate), notice: "No-show cleared for #{@candidate.name}."
    else
      @candidate.no_show!
      redirect_to candidate_path(@candidate), notice: "#{@candidate.name} marked as no-show."
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

  def set_candidate
    @candidate = current_user.candidates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to candidates_path, alert: "Candidate not found."
  end
end
