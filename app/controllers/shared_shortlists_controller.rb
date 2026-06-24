class SharedShortlistsController < ActionController::Base
  include DriveCvDownload

  layout "shared"

  before_action :set_shortlist
  before_action :require_verification, only: %i[feedback show_item no_show download_cv submit_decision]
  helper_method :verified?

  def show
    if verified?
      @items = @shortlist.shortlist_items
                         .includes(:shareable, candidate: :cv_analysis)
                         .sort_by { |i| -(i.resolved_cv_analysis&.cv_fit_score || -1) }

      if @shortlist.client_decision_submitted_at.present?
        selected = @items.select { |i| %w[final_interview hired offer_declined].include?(i.candidate&.pipeline_stage) }
        declined = @items.select { |i| i.candidate&.pipeline_stage == "not_selected" }
        @gmail_decision_url = GmailComposeUrlService.decision_url(
          shortlist:      @shortlist,
          selected_names: selected.map(&:candidate_name),
          declined_names: declined.map(&:candidate_name)
        )
      end
    end
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
                      .includes(
                        :shareable,
                        cv_analysis: { cv_attachment: :blob },
                        candidate: [
                          :cv_analysis,
                          { video_analysis: { video_attachment: :blob } }
                        ]
                      )
                      .find(params[:id])

    ordered_ids = @shortlist.shortlist_items
                             .includes(candidate: :cv_analysis)
                             .sort_by { |i| -(i.resolved_cv_analysis&.cv_fit_score || -1) }
                             .map(&:id)
    current_pos = ordered_ids.index(@item.id)
    next_id = ordered_ids[current_pos + 1] if current_pos
    @next_item_id = next_id
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

  def submit_decision
    if @shortlist.client_decision_submitted_at.present?
      redirect_to shared_shortlist_path(@shortlist.token),
                  alert: "Decision already sent on #{@shortlist.client_decision_submitted_at.strftime('%b %-d')}."
      return
    end

    @shortlist.update!(
      client_availability:          params[:client_availability].to_s.strip,
      client_decision_submitted_at: Time.current
    )

    redirect_to shared_shortlist_path(@shortlist.token), notice: "Decision sent. Use the button below to open Gmail."
  end

  def download_cv
    item = @shortlist.shortlist_items
                     .includes(cv_analysis: { cv_attachment: :blob }, candidate: :cv_analysis)
                     .find(params[:id])
    cv = item.resolved_cv_analysis

    if cv&.cv&.attached?
      redirect_to url_for(cv.cv), allow_other_host: true
      return
    end

    unless cv&.drive_file_id.present?
      redirect_to shared_shortlist_item_path(@shortlist.token, item), alert: "No CV file available."
      return
    end

    stream_drive_cv(cv)
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
