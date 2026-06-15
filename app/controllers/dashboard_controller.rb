class DashboardController < ApplicationController
  def index
    @job_roles   = current_user.job_roles.order(:title)
    @job_role_id = params[:job_role_id].presence

    base = current_user.candidates
    base = base.where(job_role_id: @job_role_id) if @job_role_id

    # ── Volume ────────────────────────────────────────────────────────────
    @total_applicants = base.count
    @screened         = base.joins(:cv_analysis)
                            .where(cv_analyses: { status: "completed" }).count

    no_show_ids       = base.where(no_show: true).ids
    show_up_ids       = base.joins(:video_analysis)
                            .where(video_analyses: { status: "completed" }).ids
    all_interview_ids = (no_show_ids + show_up_ids).uniq

    @no_show_count    = no_show_ids.size
    @show_up_count    = show_up_ids.size
    @total_interviews = all_interview_ids.size

    # ── Pipeline ──────────────────────────────────────────────────────────
    submitted_stages     = %w[client_interview final_interview hired offer_declined not_invited]
    @submitted           = base.where(pipeline_stage: submitted_stages).count
    @hired_count         = base.where(pipeline_stage: "hired").count
    @offer_declined_count = base.where(pipeline_stage: "offer_declined").count
    @total_offers        = @hired_count + @offer_declined_count

    # ── Ratios ────────────────────────────────────────────────────────────
    @app_to_screen_rate       = pct(@screened, @total_applicants)
    @no_show_rate             = pct(@no_show_count, @total_interviews)
    @screen_to_submit_rate    = pct(@submitted, @screened)
    @submit_to_interview_rate = pct(@submitted, @submitted)   # same set in this app
    @offer_declined_rate      = pct(@offer_declined_count, @total_offers)
    @offer_acceptance_rate    = pct(@hired_count, @total_offers)
    @submit_to_hire_rate      = pct(@hired_count, @submitted)
    @interview_to_offer_rate  = pct(@total_offers, @submitted)
    @screens_to_hire          = @hired_count > 0 ? (@screened.to_f / @hired_count).round(1) : nil

    # ── Timing: application-origin spans ─────────────────────────────────
    @avg_time_to_screen         = avg_days(base.pluck(:applied_at, :screened_at))
    @avg_time_to_interview      = avg_days(base.pluck(:applied_at, :interviewed_at))
    @avg_time_to_shortlist      = avg_days(base.pluck(:applied_at, :shortlisted_at))
    @avg_time_to_final          = avg_days(base.pluck(:applied_at, :final_interview_at))
    @avg_time_to_hire           = avg_days(base.pluck(:applied_at, :hired_at))

    # ── Timing: stage-to-stage spans ─────────────────────────────────────
    @avg_screen_to_interview    = avg_days(base.pluck(:screened_at, :interviewed_at))
    @avg_interview_to_shortlist = avg_days(base.pluck(:interviewed_at, :shortlisted_at))
    @avg_shortlist_to_final     = avg_days(base.pluck(:shortlisted_at, :final_interview_at))
    @avg_final_to_hire          = avg_days(base.where(pipeline_stage: "hired")
                                               .pluck(:final_interview_at, :hired_at))
  end

  private

  def pct(num, den)
    return nil if den.nil? || den == 0
    (num.to_f / den * 100).round(1)
  end

  def avg_days(pairs)
    days = pairs.filter_map { |from, to| (to - from) / 86400.0 if from && to }
    return nil if days.empty?
    (days.sum / days.size).round(1)
  end
end
