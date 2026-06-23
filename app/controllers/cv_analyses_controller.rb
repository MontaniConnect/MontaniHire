class CvAnalysesController < AuthenticatedController
  include DriveCvDownload

  before_action :set_cv_analysis, only: %i[show destroy reanalyse extracted_text download_cv]
  before_action :require_write_access!, only: %i[create bulk_create destroy reanalyse]

  def index
    @cv_analyses = current_organization.cv_analyses.includes(:job_role).order(created_at: :desc)
  end

  def create
    @cv_analysis = current_organization.cv_analyses.build(create_params.merge(user: current_user))

    if @cv_analysis.save
      current_organization.candidates.create!(user: current_user,
        name:           @cv_analysis.candidate_name.presence || @cv_analysis.display_name,
        job_role:       @cv_analysis.job_role,
        cv_analysis:    @cv_analysis,
        pipeline_stage: "cv_review"
      )
      CvProcessingJob.perform_later(@cv_analysis.id)
      redirect_to cv_analysis_path(@cv_analysis)
    else
      @cv_analyses = current_organization.cv_analyses.includes(:job_role).order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def bulk_create
    job_role = current_organization.job_roles.find_by(id: params[:job_role_id])
    unless job_role
      redirect_to cv_analyses_path, alert: "Please select a job role."
      return
    end

    files = Array(params[:cvs]).select(&:present?)
    if files.empty?
      redirect_to cv_analyses_path, alert: "No files selected."
      return
    end

    created = 0
    files.each do |file|
      name = File.basename(file.original_filename.to_s, ".*")
               .gsub(/[-_]/, " ")
               .gsub(/\b\w/) { |c| c.upcase }
               .strip
      name = "Candidate #{created + 1}" if name.blank?

      cv_analysis = current_organization.cv_analyses.new(
        user:           current_user,
        cv:             file,
        job_role:       job_role,
        candidate_name: name
      )
      next unless cv_analysis.save

      current_organization.candidates.create!(
        user:           current_user,
        name:           name,
        job_role:       job_role,
        cv_analysis:    cv_analysis,
        pipeline_stage: "cv_review"
      )
      CvProcessingJob.perform_later(cv_analysis.id)
      created += 1
    end

    redirect_to cv_analyses_path,
                notice: "#{created} CV#{"s" if created != 1} uploaded and queued for analysis."
  end

  def show
    @candidate = current_organization.candidates.find_by(cv_analysis_id: @cv_analysis.id)
  end

  def destroy
    candidate = @cv_analysis.candidate

    if candidate&.video_analysis.present?
      return redirect_to cv_analyses_path,
        alert: "#{candidate.name} has a video interview. Remove the video interview first before deleting this CV."
    end

    candidate.destroy if candidate
    @cv_analysis.destroy
    redirect_to cv_analyses_path, notice: "\"#{@cv_analysis.display_name}\" removed."
  end

  def reanalyse
    if @cv_analysis.extracted_text.blank?
      redirect_to cv_analysis_path(@cv_analysis), alert: "No extracted text to re-analyse."
      return
    end
    @cv_analysis.update!(status: "analyzing", error_message: nil,
                         score: nil, summary: nil, structured_feedback: {})
    CvClaudeAnalysisService.new(analysis: @cv_analysis).call
    redirect_to cv_analysis_path(@cv_analysis), notice: "Re-analysis complete."
  rescue => e
    @cv_analysis.transition_to!("failed", error: e.message)
    redirect_to cv_analysis_path(@cv_analysis), alert: "Re-analysis failed: #{e.message}"
  end

  def extracted_text
    if @cv_analysis.extracted_text.blank?
      redirect_to cv_analysis_path(@cv_analysis), alert: "No extracted text available."
      return
    end
    filename = "#{@cv_analysis.display_name.parameterize}-cv.txt"
    send_data @cv_analysis.extracted_text, filename: filename, type: "text/plain"
  end

  def download_cv
    if @cv_analysis.cv.attached?
      redirect_to url_for(@cv_analysis.cv), allow_other_host: true
      return
    end

    unless @cv_analysis.drive_file_id.present?
      redirect_to cv_analysis_path(@cv_analysis), alert: "No CV file available."
      return
    end

    stream_drive_cv(@cv_analysis)
  end

  private

  def create_params
    params.require(:cv_analysis).permit(:cv, :job_role_id, :candidate_name,
                                        :drive_file_id, :drive_file_name)
  end

  def set_cv_analysis
    @cv_analysis = current_organization.cv_analyses.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to cv_analyses_path, alert: "CV analysis not found."
  end
end
