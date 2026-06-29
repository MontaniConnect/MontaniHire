class OutcomeExamplesBuilder
  def initialize(role:, exclude_candidate: nil)
    @role              = role
    @exclude_candidate = exclude_candidate
  end

  def build(intro:)
    return nil unless @role

    items = ShortlistItem.hm_decided_for_role(@role, exclude: @exclude_candidate)
    return nil if items.empty?

    invited     = items.select { |i| i.client_status == "approved" }
    not_invited = items.select { |i| i.client_status == "rejected" }

    lines = Array(intro).dup

    if invited.any?
      lines << "\n### Invited to Final Interview"
      invited.first(3).each_with_index { |item, i| lines << format_example(item, i + 1) }
    end

    if not_invited.any?
      lines << "\n### Not Invited to Final Interview"
      not_invited.first(3).each_with_index { |item, i| lines << format_example(item, i + 1) }
    end

    lines.compact.join("\n")
  end

  private

  def format_example(_item, _index)
    raise NotImplementedError, "#{self.class}#format_example is not implemented"
  end

  def hm_lines(item)
    [].tap do |l|
      l << "  HM rating: #{item.client_rating}/5" if item.client_rating.present?
      l << "  HM notes: #{item.client_comment}"   if item.client_comment.present?
    end
  end
end

class OutcomeExamplesBuilder::Interview < OutcomeExamplesBuilder
  private

  def format_example(item, index)
    va = item.resolved_video_analysis
    ep = va&.episode_score
    return nil unless va&.structured_feedback.present? && ep.present?

    fb   = va.structured_feedback
    jd   = fb["jd_fit_score"]
    dims = fb["episode_dimensions"] || {}

    score_line = []
    score_line << "Episode Score: #{ep}/10"
    score_line << "JD fit: #{jd}/10" if jd.present?

    lines = [ "\nExample #{index} (#{score_line.join(' · ')}):" ]

    if dims.any?
      dim_order = %w[relevance_discipline ownership_language outcome_orientation adaptability_signal communication_clarity]
      lines << "  Episode dimensions:"
      dim_order.each do |dim|
        next unless dims[dim].present?
        lines << "    #{dim.ljust(24)} #{dims[dim]}"
      end
    end

    lines << "  Strengths: #{Array(fb['strengths']).first(3).join('; ')}"           if fb["strengths"].present?
    lines << "  Communication: #{fb['communication_quality']}"                      if fb["communication_quality"].present?
    lines << "  Red flags: #{Array(fb['red_flags']).first(2).join('; ')}"            if fb["red_flags"].present?
    lines << "  Rationale: #{fb['decision_rationale']}"                              if fb["decision_rationale"].present?
    lines.concat(hm_lines(item))
    lines.join("\n")
  end
end

class OutcomeExamplesBuilder::CvScreening < OutcomeExamplesBuilder
  private

  def format_example(item, index)
    cv = item.resolved_cv_analysis
    return nil unless cv&.structured_feedback.present? && cv.cv_fit_score.present?

    fb         = cv.structured_feedback
    score_line = "CV Fit Score: #{fb['cv_fit_score']}/10"
    lines      = [ "\nExample #{index} (#{score_line}, recommendation: #{fb['recommendation']}):" ]

    cov = Array(fb["cv_requirements_coverage"])
    if cov.any?
      lines << "  Must-have coverage:"
      cov.each do |r|
        tag  = { "evidenced" => "evidenced", "partial" => "partial  ", "not evidenced" => "missing  " }[r["coverage"]] || "unknown  "
        line = "    #{tag} | #{r['requirement']}"
        line += " — #{r['evidence']}" if r["evidence"].present?
        lines << line
      end
    else
      lines << "  Matched must-haves: #{Array(fb['matched_skills']).first(4).join(', ')}" if fb["matched_skills"].present?
      lines << "  Missing must-haves: #{Array(fb['missing_skills']).first(3).join(', ')}" if fb["missing_skills"].present?
    end

    lines << "  Evidence gaps: #{Array(fb['skill_evidence_gaps']).first(2).join(', ')}" if fb["skill_evidence_gaps"].present?
    lines << "  Career progression: #{fb['career_progression']}"                        if fb["career_progression"].present?
    lines << "  Experience level fit: #{fb['experience_level_fit']}"                    if fb["experience_level_fit"].present?
    lines << "  Rationale: #{fb['decision_rationale']}"                                  if fb["decision_rationale"].present?
    lines.concat(hm_lines(item))
    lines.join("\n")
  end
end
