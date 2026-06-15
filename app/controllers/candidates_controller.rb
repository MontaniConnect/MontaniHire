class CandidatesController < AuthenticatedController
  before_action :set_candidate, only: %i[show update destroy]

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
