class ShortlistItemsController < AuthenticatedController
  def create
    shortlist = current_user.shortlists.find(params[:shortlist_id])

    if params[:candidate_id].present?
      candidate = current_user.candidates.find(params[:candidate_id])
      check_compliance_flags!(cv_analysis: candidate.cv_analysis, video_analysis: candidate.video_analysis) && return
      item = shortlist.shortlist_items.find_or_initialize_by(candidate: candidate)
      item.cv_analysis    = candidate.cv_analysis
      item.video_analysis = candidate.video_analysis
      item.save!
      candidate.shortlist_for_client!
      redirect_back fallback_location: shortlist_path(shortlist),
                    notice: "#{candidate.name} added to \"#{shortlist.title}\"."
    else
      primary = candidate_from_params(:shareable_type, :shareable_id)
      if primary.nil?
        redirect_back fallback_location: shortlists_path, alert: "Candidate not found."
        return
      end
      item = shortlist.shortlist_items.find_or_initialize_by(shareable: primary)
      case primary
      when CvAnalysis    then item.cv_analysis    = primary
      when VideoAnalysis then item.video_analysis = primary
      end
      if params[:companion_cv_analysis_id].present?
        item.cv_analysis = current_user.cv_analyses.find_by(id: params[:companion_cv_analysis_id])
      end
      if params[:companion_video_analysis_id].present?
        item.video_analysis = current_user.video_analyses.find_by(id: params[:companion_video_analysis_id])
      end
      check_compliance_flags!(cv_analysis: item.cv_analysis, video_analysis: item.video_analysis) && return
      candidate = Candidate.find_by(cv_analysis_id: item.cv_analysis_id) ||
                  Candidate.find_by(video_analysis_id: item.video_analysis_id)
      item.candidate = candidate if candidate
      item.save!
      candidate&.shortlist_for_client!
      redirect_back fallback_location: shortlist_path(shortlist),
                    notice: "#{primary.display_name} added to \"#{shortlist.title}\"."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to shortlists_path, alert: "Shortlist not found."
  end

  def update
    item = ShortlistItem.joins(:shortlist)
                        .where(shortlists: { user_id: current_user.id })
                        .find(params[:id])

    if params[:cv_analysis_id].present?
      item.cv_analysis = current_user.cv_analyses.find_by(id: params[:cv_analysis_id])
    end
    if params[:video_analysis_id].present?
      item.video_analysis = current_user.video_analyses.find_by(id: params[:video_analysis_id])
    end

    item.save!
    redirect_to shortlist_path(item.shortlist), notice: "Files updated."
  rescue ActiveRecord::RecordNotFound
    redirect_to shortlists_path, alert: "Item not found."
  end

  def destroy
    item = ShortlistItem.joins(:shortlist)
                        .where(shortlists: { user_id: current_user.id })
                        .find(params[:id])
    shortlist  = item.shortlist
    candidate  = item.candidate
    item.destroy
    candidate.revert! if candidate&.pipeline_stage == "client_interview"
    redirect_to shortlist_path(shortlist),
                notice: "#{candidate&.name || "Candidate"} removed from shortlist and moved back to Preliminary Interview."
  end

  private

  def candidate_from_params(type_key, id_key)
    type = params[type_key]
    id   = params[id_key]
    case type
    when "CvAnalysis"    then current_user.cv_analyses.find_by(id: id)
    when "VideoAnalysis" then current_user.video_analyses.find_by(id: id)
    end
  end

  def compliance_flags_for(cv_analysis: nil, video_analysis: nil)
    flags = []
    if cv_analysis
      fb = cv_analysis.structured_feedback || {}
      Array(fb["credential_flags"]).each { |f| flags << "Credential flag: #{f}" }
    end
    flags
  end

  def check_compliance_flags!(cv_analysis: nil, video_analysis: nil)
    return false if params[:flags_acknowledged] == "true"
    flags = compliance_flags_for(cv_analysis: cv_analysis, video_analysis: video_analysis)
    return false if flags.empty?
    redirect_back fallback_location: shortlists_path,
                  alert: "This candidate has compliance flags that must be acknowledged before shortlisting. Please review the analysis page and confirm."
    true
  end
end
