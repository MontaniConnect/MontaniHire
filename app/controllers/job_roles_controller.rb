class JobRolesController < AuthenticatedController
  before_action :set_job_role, only: %i[show edit update destroy extract_requirements]
  before_action :require_write_access!, only: %i[create update destroy extract_requirements]

  def index
    @job_roles = current_organization.job_roles.order(created_at: :desc)
  end

  def show
    @tab = params[:tab].presence || "overview"

    if @tab == "calibration"
      confirmed = Candidate
        .where(job_role: @job_role, pipeline_stage: %w[final_interview not_invited])
        .where.not(outcome_confirmed_at: nil)
        .order(outcome_confirmed_at: :desc)
        .includes(:video_analysis, :cv_analysis)

      @calibration_invited     = confirmed.select { |c| c.pipeline_stage == "final_interview" }
      @calibration_not_invited = confirmed.select { |c| c.pipeline_stage == "not_invited" }
      @calibration_examples    = confirmed.to_a
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
    @job_role = current_organization.job_roles.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to job_roles_path, alert: "Role not found."
  end
end
