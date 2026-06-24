module Candidates
  class PipelineController < BaseController
    def advance
      @candidate.advance_to_interview!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} advanced to preliminary interview."
    end

    def reject
      @candidate.reject!
      redirect_back fallback_location: candidates_path,
                    notice: "#{@candidate.name} marked as rejected."
    end

    def revert
      was_shortlisted = @candidate.pipeline_stage == "client_interview"
      @candidate.revert!
      notice = was_shortlisted \
        ? "#{@candidate.name} moved back to Preliminary Interview and removed from all shortlists."
        : "#{@candidate.name} reverted to CV Review."
      redirect_to candidate_path(@candidate), notice: notice
    end

    def final_interview
      @candidate.advance_to_final_interview!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} confirmed for final interview."
    end

    def not_invited
      @candidate.mark_not_invited!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} marked as not invited."
    end

    def hire
      @candidate.hire!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} marked as hired."
    end

    def offer_declined
      @candidate.mark_offer_declined!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} marked as offer declined."
    end

    def not_selected
      @candidate.mark_not_selected!
      redirect_to candidate_path(@candidate),
                  notice: "#{@candidate.name} marked as not selected."
    end

    def confirm_outcome
      if @candidate.outcome_confirmed?
        @candidate.update!(outcome_confirmed_at: nil, outcome_note: nil)
        redirect_back fallback_location: candidate_path(@candidate),
                      notice: "Outcome confirmation removed for #{@candidate.name}."
      else
        note = params[:outcome_note].to_s.strip.presence
        @candidate.update!(outcome_confirmed_at: Time.current, outcome_note: note)
        redirect_back fallback_location: candidate_path(@candidate),
                      notice: "Outcome confirmed for #{@candidate.name}. This will calibrate future analyses."
      end
    end

    def toggle_no_show
      if @candidate.no_show?
        @candidate.undo_no_show!
        redirect_to candidate_path(@candidate), notice: "No-show cleared for #{@candidate.name}."
      else
        @candidate.no_show!
        redirect_to candidate_path(@candidate), notice: "#{@candidate.name} marked as no-show."
      end
    end

    def toggle_prelim_no_show
      if @candidate.preliminary_interview_no_show?
        @candidate.undo_prelim_no_show!
        redirect_to candidate_path(@candidate), notice: "Preliminary interview no-show cleared for #{@candidate.name}."
      else
        @candidate.mark_prelim_no_show!
        redirect_to candidate_path(@candidate), notice: "#{@candidate.name} marked as no-show (preliminary interview)."
      end
    end
  end
end
