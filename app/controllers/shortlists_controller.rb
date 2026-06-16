class ShortlistsController < AuthenticatedController
  before_action :set_shortlist, only: %i[show edit update destroy]
  before_action :require_write_access!, only: %i[create update destroy]

  def index
    @shortlists = current_organization.shortlists.order(created_at: :desc)
  end

  def show
    @items = @shortlist.shortlist_items.includes(:shareable, :candidate)
  end

  def new
    @shortlist = current_organization.shortlists.build
    @candidate = candidate_from_params
  end

  def create
    @shortlist = current_organization.shortlists.build(shortlist_params.merge(user: current_user))
    if @shortlist.save
      add_candidate_to(@shortlist)
      redirect_to shortlist_path(@shortlist), notice: "Shortlist created."
    else
      @candidate = candidate_from_params
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @shortlist.update(shortlist_params)
      redirect_to shortlist_path(@shortlist), notice: "Shortlist updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shortlist.destroy
    redirect_to shortlists_path, notice: "Shortlist deleted."
  end

private

  def shortlist_params
    params.require(:shortlist).permit(:title, :client_email, :message, :client_name, :client_logo_url)
  end

  def set_shortlist
    @shortlist = current_organization.shortlists.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shortlists_path, alert: "Shortlist not found."
  end

  def candidate_from_params
    type  = params[:type]
    id    = params[:candidate_id]
    return nil unless type && id
    case type
    when "CvAnalysis"    then current_organization.cv_analyses.find_by(id: id)
    when "VideoAnalysis" then current_organization.video_analyses.find_by(id: id)
    end
  end

  def add_candidate_to(shortlist)
    candidate = candidate_from_params
    return unless candidate
    shortlist.shortlist_items.find_or_create_by!(
      shareable: candidate
    )
  end
end
