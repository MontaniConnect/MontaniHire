class JobRolesController < AuthenticatedController
  before_action :set_job_role, only: %i[show edit update destroy extract_requirements]
  before_action :require_write_access!, only: %i[create update destroy extract_requirements]

  def index
    @job_roles = current_organization.job_roles.includes(:video_analyses, :cv_analyses).order(created_at: :desc)
  end

  def show
    @tab = params[:tab].presence || "overview"

    if @tab == "calibration"
      completed_video_ids = VideoAnalysis.where(status: "completed").select(:id)

      @calibration_invited = Candidate
        .where(job_role: @job_role, pipeline_stage: %w[hired offer_declined], final_interview_no_show: false)
        .where(video_analysis_id: completed_video_ids)
        .includes(:video_analysis, :cv_analysis)
        .order(updated_at: :desc)

      @calibration_not_invited = Candidate
        .where(job_role: @job_role, final_interview_no_show: false)
        .where("pipeline_stage = 'not_invited' OR (pipeline_stage = 'not_selected' AND NOT preliminary_interview_no_show)")
        .where(video_analysis_id: completed_video_ids)
        .includes(:video_analysis, :cv_analysis)
        .order(updated_at: :desc)

      @calibration_examples = (@calibration_invited.to_a + @calibration_not_invited.to_a)
        .sort_by(&:updated_at).reverse
    end
  end

  def new
    @job_role = current_organization.job_roles.build
    @clients  = current_organization.clients.order(:name)
  end

  def create
    @job_role = current_organization.job_roles.build(job_role_params.merge(user: current_user))
    if @job_role.save
      redirect_to job_roles_path, notice: "Role \"#{@job_role.title}\" created."
    else
      @clients = current_organization.clients.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @clients = current_organization.clients.order(:name)
  end

  def update
    if @job_role.update(job_role_params)
      redirect_to job_roles_path, notice: "Role updated."
    else
      @clients = current_organization.clients.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def extract_requirements
    result = JobRoleRequirementsService.new(job_role: @job_role).call
    @job_role.update!(
      must_have_requirements:    result[:must_have],
      nice_to_have_requirements: result[:nice_to_have]
    )
    redirect_to edit_job_role_path(@job_role),
      notice: "Extracted #{result[:must_have].size} must-have and #{result[:nice_to_have].size} nice-to-have requirements. Review and save to lock them."
  rescue => e
    redirect_to edit_job_role_path(@job_role), alert: "Extraction failed: #{e.message}"
  end

  def destroy
    @job_role.destroy
    redirect_to job_roles_path, notice: "Role deleted."
  end

  private

  def job_role_params
    permitted = params.require(:job_role).permit(
      :title, :experience_level, :required_skills, :responsibilities, :description, :client_id,
      must_have_requirements: [], nice_to_have_requirements: [],
      score_weights: {}
    )
    permitted[:must_have_requirements]    = Array(permitted[:must_have_requirements]).map(&:strip).reject(&:blank?)
    permitted[:nice_to_have_requirements] = Array(permitted[:nice_to_have_requirements]).map(&:strip).reject(&:blank?)
    if permitted[:score_weights].present?
      permitted[:score_weights] = permitted[:score_weights].transform_values(&:to_i)
    end
    permitted
  end

  def set_job_role
    @job_role = current_organization.job_roles.includes(:video_analyses, :cv_analyses).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to job_roles_path, alert: "Role not found."
  end
end
