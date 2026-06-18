namespace :analysis do
  desc <<~DESC
    Re-run completed analyses sequentially to pick up prompt changes.

    Options (set as env vars):
      PREVIEW=1       Run only 3 CV + 3 interview analyses, then stop. Use this to check scores before a full re-run.
      STALE=1         Only re-run analyses whose prompt_version differs from the current version. Skips already-current analyses.
      JOB_ROLE=id     Limit to a specific job role ID.

    Examples:
      rails analysis:rerun PREVIEW=1
      rails analysis:rerun STALE=1
      rails analysis:rerun STALE=1 JOB_ROLE=3
      rails analysis:rerun
  DESC
  task rerun: :environment do
    preview   = ENV["PREVIEW"] == "1"
    stale     = ENV["STALE"]   == "1"
    role_id   = ENV["JOB_ROLE"].presence

    cv_current = CvClaudeAnalysisService::PROMPT_VERSION
    va_current = ClaudeAnalysisService::PROMPT_VERSION

    cv_scope = CvAnalysis.where(status: "completed")
    va_scope = VideoAnalysis.where(status: "completed")

    cv_scope = cv_scope.where(job_role_id: role_id) if role_id
    va_scope = va_scope.where(job_role_id: role_id) if role_id

    if stale
      cv_scope = cv_scope.where("prompt_version IS NULL OR prompt_version != ?", cv_current)
      va_scope = va_scope.where("prompt_version IS NULL OR prompt_version != ?", va_current)
    end

    cv_total = cv_scope.count
    va_total = va_scope.count
    total    = cv_total + va_total

    if total.zero?
      puts stale ? "All analyses are already on the current prompt version. Nothing to do." \
                 : "No completed analyses found."
      next
    end

    limit = preview ? 3 : nil

    # Cost estimate: first call of each type creates the cache, rest read it
    cv_cost = cv_scope.limit(limit).count * 0.054
    va_first = [ va_scope.limit(limit).count, 1 ].min * 0.053
    va_rest  = ([ va_scope.limit(limit).count - 1, 0 ].max) * 0.042
    est_cost = (cv_cost + va_first + va_rest).round(3)

    puts ""
    puts preview ? "=== PREVIEW MODE (3 of each) ===" : "=== FULL RE-RUN ==="
    puts stale   ? "  Scope : stale only (prompt_version != current)" \
                 : "  Scope : all completed analyses"
    puts "  CV analyses    : #{cv_scope.limit(limit).count}#{stale ? " of #{cv_total} total" : ""}"
    puts "  Interview      : #{va_scope.limit(limit).count}#{stale ? " of #{va_total} total" : ""}"
    puts "  Est. cost      : ~$#{est_cost} (sequential, cache-warm after first call)"
    puts "  CV version     : #{cv_current}"
    puts "  Interview ver. : #{va_current}"
    puts ""

    errors = []

    # ── CV analyses first so updated screening context is ready for interviews ──
    cv_scope.limit(limit).each do |cv|
      name = cv.display_name
      old_score = cv.score
      print "  [CV] #{name} (was #{old_score || "—"}/10)... "
      begin
        cv.update!(status: "pending")
        CvClaudeAnalysisService.new(cv).call
        cv.reload
        delta = old_score ? " (#{cv.score.to_f >= old_score.to_f ? "+" : ""}#{(cv.score.to_f - old_score.to_f).round(1)})" : ""
        puts "#{cv.score}/10#{delta}"
      rescue => e
        puts "FAILED: #{e.message}"
        errors << "[CV #{cv.id}] #{name}: #{e.message}"
        cv.transition_to!("failed", error: e.message)
      end
    end

    # ── Interview analyses — confirmed candidates first so their updated scores
    #    are already in the database before non-confirmed candidates run and
    #    pull calibration data.
    confirmed_va_ids = Candidate.where.not(outcome_confirmed_at: nil)
                                .pluck(:video_analysis_id).compact.to_set

    ordered_va = va_scope.to_a.sort_by { |va| confirmed_va_ids.include?(va.id) ? 0 : 1 }
    ordered_va = ordered_va.first(limit) if limit

    ordered_va.each do |va|
      name = va.display_name
      old_score = va.score

      candidate = Candidate.find_by(video_analysis_id: va.id)
      unless candidate&.cv_analysis&.completed?
        puts "  [INT] #{name} — skipped (no completed CV analysis)"
        next
      end

      confirmed = confirmed_va_ids.include?(va.id)
      print "  [INT] #{name}#{confirmed ? " [confirmed]" : ""} (was #{old_score || "—"}/10)... "
      begin
        va.update!(status: "pending")
        ClaudeAnalysisService.new(va).call
        va.reload
        delta = old_score ? " (#{va.score.to_f >= old_score.to_f ? "+" : ""}#{(va.score.to_f - old_score.to_f).round(1)})" : ""
        puts "#{va.score}/10#{delta}"
      rescue => e
        puts "FAILED: #{e.message}"
        errors << "[INT #{va.id}] #{name}: #{e.message}"
        va.transition_to!("failed", error: e.message)
      end
    end

    puts ""
    if errors.any?
      puts "Completed with #{errors.size} error(s):"
      errors.each { |e| puts "  #{e}" }
    else
      puts preview ? "Preview complete. Run without PREVIEW=1 to re-run all." \
                   : "Done. All analyses updated to current prompt version."
    end
    puts ""
  end
end
