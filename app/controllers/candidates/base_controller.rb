module Candidates
  class BaseController < AuthenticatedController
    before_action :set_candidate

    private

    def set_candidate
      @candidate = current_user.candidates.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to candidates_path, alert: "Candidate not found."
    end
  end
end
