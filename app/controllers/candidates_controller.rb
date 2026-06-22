class CandidatesController < AuthenticatedController
  before_action :set_candidate, only: %i[show update destroy]
  before_action :require_write_access!, only: %i[update destroy]

  def index
    @q           = params[:q].to_s.strip
    @client_id   = params[:client_id].presence
    @job_role_id = params[:job_role_id].presence

    @clients = current_organization.clients.order(:name)

    base_roles = current_organization.job_roles
                                     .where(id: current_organization.candidates.where.not(job_role_id: nil).select(:job_role_id))
    @job_roles = (@client_id ? base_roles.where(client_id: @client_id) : base_roles).order(:title)

    scope = current_organization.candidates.includes(:job_role, :cv_analysis, :video_analysis)
                                .order(created_at: :desc)

    if @q.present?
      scope = scope.where(
        "candidates.name ILIKE :q OR job_roles.title ILIKE :q",
        q: "%#{@q}%"
      ).references(:job_role)
    end

    if @job_role_id
      scope = scope.where(job_role_id: @job_role_id)
    elsif @client_id
      client_role_ids = current_organization.job_roles.where(client_id: @client_id).pluck(:id)
      scope = scope.where(job_role_id: client_role_ids)
    end

    @candidates = scope

    ph_tz          = ActiveSupport::TimeZone["Asia/Manila"]
    now_ph         = Time.current.in_time_zone(ph_tz)
    today_start    = now_ph.beginning_of_day.utc
    today_end      = now_ph.end_of_day.utc
    upcoming_end   = (now_ph + 7.days).end_of_day.utc

    org_bookings = SlotBooking.joins(:candidate)
                              .where(candidates: { organization_id: current_organization.id })
                              .includes(candidate: :job_role)
                              .order(:starts_at)

    @today_bookings    = org_bookings.where(starts_at: today_start..today_end)
    @upcoming_bookings = org_bookings.where(starts_at: (today_end + 1.second)..upcoming_end)
  end

  def show
    @shortlist_item = ShortlistItem.joins(:shortlist)
                                   .where(shortlists: { organization_id: current_organization.id })
                                   .find_by(candidate_id: @candidate.id)
    @candidate.update_columns(intake_viewed_at: Time.current) if @candidate.intake_unread?
    if @candidate.screened_at.blank? && @candidate.cv_analysis.present?
      @candidate.update_columns(screened_at: @candidate.cv_analysis.created_at)
    end
    if @candidate.shortlisted_at.blank? && @candidate.shortlist_items.exists?
      @candidate.update_columns(shortlisted_at: @candidate.shortlist_items.minimum(:created_at))
    end
    if @candidate.final_interview_at.blank? &&
       %w[final_interview hired offer_declined not_selected].include?(@candidate.pipeline_stage)
      booked_at = @candidate.slot_booking&.starts_at
      @candidate.update_columns(final_interview_at: booked_at || Time.current)
    end
    if @candidate.hired_at.blank? && @candidate.pipeline_stage == "hired"
      @candidate.update_columns(hired_at: Time.current)
    end
  end

  def update
    new_role = current_organization.job_roles.find_by(id: params[:candidate][:job_role_id])
    if new_role
      @candidate.update!(job_role: new_role)
      @candidate.cv_analysis&.update!(job_role: new_role)
      @candidate.video_analysis&.update!(job_role: new_role)
      redirect_to candidate_path(@candidate), notice: "Job role updated to \"#{new_role.title}\"."
    else
      redirect_to candidate_path(@candidate), alert: "Invalid job role."
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
    @candidate = current_organization.candidates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to candidates_path, alert: "Candidate not found."
  end
end
