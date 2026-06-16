class SharedShortlistsController < ActionController::Base
  layout "shared"

  before_action :set_shortlist
  before_action :require_verification, only: %i[feedback show_item no_show]
  helper_method :verified?

  def show
    if verified?
      @items = @shortlist.shortlist_items
                         .includes(:shareable, candidate: :cv_analysis)
                         .sort_by { |i| -(i.resolved_cv_analysis&.cv_fit_score || -1) }
    end
    # renders the email gate or the candidate list depending on verified?
  end

  def verify
    email = params[:email].to_s.strip
    if @shortlist.verified_by?(email)
      session["verified_#{@shortlist.token}"] = true
      redirect_to shared_shortlist_path(@shortlist.token),
                  notice: "Access granted."
    else
      redirect_to shared_shortlist_path(@shortlist.token),
                  alert: "That email doesn't match. Please check with the person who shared this link."
    end
  end

  def show_item
    @item = @shortlist.shortlist_items
                      .includes(:shareable, candidate: { video_analysis: { video_attachment: :blob } })
                      .find(params[:id])
  end

  def feedback
    item       = @shortlist.shortlist_items.includes(:candidate).find(params[:id])
    rating     = params[:client_rating].to_i
    new_status = params[:client_status].presence || item.client_status
    item.update!(
      client_status:  new_status,
      client_comment: params[:client_comment],
      client_rating:  rating.between?(1, 5) ? rating : nil
    )
    item.sync_candidate_stage!(new_status)
    redirect_to shared_shortlist_item_path(@shortlist.token, item),
                notice: "Feedback saved."
  end

  def no_show
    item = @shortlist.shortlist_items.includes(:candidate).find(params[:id])
    item.toggle_final_interview_no_show!
    notice = item.final_interview_no_show? ? "Marked as no show." : "No show cleared."
    redirect_to shared_shortlist_item_path(@shortlist.token, item), notice: notice
  end

  private

  def set_shortlist
    @shortlist = Shortlist.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render plain: "This link is invalid or has expired.", status: :not_found
  end

  def verified?
    session["verified_#{@shortlist.token}"] == true
  end

  def require_verification
    unless verified?
      redirect_to shared_shortlist_path(@shortlist.token),
                  alert: "Please verify your email first."
    end
  end
end
