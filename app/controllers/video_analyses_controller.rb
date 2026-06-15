class VideoAnalysesController < ApplicationController
  before_action :set_video_analysis, only: %i[show destroy reanalyse transcript]

  def new
    @candidate = current_user.candidates.find_by(id: params[:candidate_id])
  end

  def index
    @video_analyses = current_user.video_analyses.includes(:job_role).order(created_at: :desc)
    respond_to do |format|
      format.html
      format.json { render json: @video_analyses.map { |a| serialize(a) } }
    end
  end

  def create
    @video_analysis = current_user.video_analyses.build(create_params)

    if @video_analysis.save
      if params[:candidate_id].present?
        candidate = current_user.candidates.find_by(id: params[:candidate_id])
        candidate&.update!(video_analysis: @video_analysis)
      end
      VideoProcessingJob.perform_later(@video_analysis.id)
      respond_to do |format|
        format.html { redirect_to video_analysis_path(@video_analysis) }
        format.json { render json: serialize(@video_analysis), status: :created }
      end
    else
      @video_analyses = current_user.video_analyses.includes(:job_role).order(created_at: :desc)
      respond_to do |format|
        format.html { render :index, status: :unprocessable_entity }
        format.json { render json: { errors: @video_analysis.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def show
    @candidate = current_user.candidates.find_by(video_analysis_id: @video_analysis.id)
    respond_to do |format|
      format.html
      format.json { render json: serialize(@video_analysis) }
    end
  end

  def destroy
    @video_analysis.destroy
    redirect_to video_analyses_path, notice: "\"#{@video_analysis.display_name}\" removed."
  end

  def reanalyse
    if @video_analysis.transcript.blank?
      redirect_to video_analysis_path(@video_analysis), alert: "No transcript to re-analyse."
      return
    end
    candidate = Candidate.find_by(video_analysis_id: @video_analysis.id)
    unless candidate&.cv_analysis&.completed?
      redirect_to video_analysis_path(@video_analysis), alert: "CV analysis must be completed before running interview analysis."
      return
    end
    @video_analysis.update!(status: "analyzing", error_message: nil,
                            score: nil, summary: nil, structured_feedback: {})
    ClaudeAnalysisService.new(@video_analysis).call
    redirect_to video_analysis_path(@video_analysis), notice: "Re-analysis complete."
  rescue => e
    @video_analysis.transition_to!("failed", error: e.message)
    redirect_to video_analysis_path(@video_analysis), alert: "Re-analysis failed: #{e.message}"
  end

  def transcript
    if @video_analysis.transcript.blank?
      redirect_to video_analysis_path(@video_analysis), alert: "No transcript available."
      return
    end
    filename = "#{@video_analysis.display_name.parameterize}-transcript.txt"
    send_data @video_analysis.transcript, filename: filename, type: "text/plain"
  end

  private

  def create_params
    params.require(:video_analysis).permit(:video, :job_role_id, :candidate_name,
                                           :drive_file_id, :drive_file_name)
  end

  def set_video_analysis
    @video_analysis = current_user.video_analyses.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to video_analyses_path, alert: "Analysis not found." }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def serialize(analysis)
    {
      id: analysis.id,
      candidate_name: analysis.candidate_name,
      filename: analysis.display_name,
      job_role: analysis.job_role&.title,
      status: analysis.status,
      transcript: analysis.transcript,
      summary: analysis.summary,
      structured_feedback: analysis.structured_feedback,
      score: analysis.score,
      error_message: analysis.error_message,
      created_at: analysis.created_at,
      updated_at: analysis.updated_at
    }
  end
end
