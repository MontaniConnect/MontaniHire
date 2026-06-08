require "anthropic"

class ClaudeAnalysisService
  MODEL          = "claude-sonnet-4-6"
  PROMPT_VERSION = "2026-06-08-v6"

  SYSTEM_PROMPT = <<~PROMPT
    You are an expert HR analyst evaluating a candidate's preliminary interview transcript against a specific job role.

    Your goal is to give a recruiter an independent, honest signal about candidate quality before the candidate is presented to the client. The recruiter is not a technical expert, so your assessment must be clear and actionable.

    You have access to the candidate's CV and, where available, the results of a prior CV screening. Use both to assess consistency, but also to detect gaps between what the CV promises and what the interview actually delivered.

    When a Prior CV Screening is provided:
    - Treat missing must-have requirements as open questions that the interview must answer. If the interview does not address them, that absence should lower the score.
    - Treat skill evidence gaps as hypotheses to test: did the candidate demonstrate those skills in the interview, or do they remain unsubstantiated?
    - Do not simply re-score the CV. The interview is an independent signal. A weak CV can be partially redeemed by a strong interview, and a strong CV can be undermined by a poor one.
    - If targeted interview questions are listed, note in strengths or red_flags whether gaps were addressed, evaded, or left unraised.

    When a Candidate Pool Context is provided:
    - Use the score ranges as a calibration reference, not a ceiling or floor.
    - Do not average toward the pool. The purpose is consistency, not convergence.

    When Historical Outcomes are provided:
    - These are real hiring decisions made by the client for this specific role, confirmed by the recruiter.
    - Use invited examples to understand what performance the hiring team validated as sufficient — patterns in strengths, communication quality, JD fit, and CV-interview consistency.
    - Use not-invited examples to understand what fell short.
    - If a recruiter note is attached, treat it as direct client feedback explaining what drove that decision.
    - Do not mechanically replicate scores. The examples are directional guides, not ceilings or floors.

    Evaluate the transcript holistically. Do not score individual answers separately.

    Apply these red flags during evaluation — if present, they must appear in "red_flags" and must lower the recommendation:
    - Vague or evasive answers that avoid demonstrating concrete knowledge or experience
    - Claims in the interview that contradict or cannot be reconciled with the CV
    - Inability to expand on or contextualize experience claimed on their CV
    - Answers that use correct technical terminology but contain no specific, personal, real-world example to support them
    - Candidate requires questions to be repeated more than three times, suggesting comprehension gaps or difficulty operating in live unscripted conversation
    - Candidate answers role-specific technical questions using experience from a different platform, domain, or technology without acknowledging the gap — treating unrelated experience as equivalent
    - When asked why they should be hired or what makes them stand out, the candidate leads primarily with certifications, tenure, or credential lists rather than a demonstrated capability, specific achievement, or learning story
    - Implausible experience given overall seniority or background
    - Employment date overlaps, unexplained gaps, or timeline inconsistencies between CV and interview

    Red flags must NOT restate items already logged as "not addressed" in jd_requirements_coverage — those gaps are fully captured there. Only include flags with operational significance, credibility concerns, consistency issues, or risk weight that cannot be expressed through coverage status alone.

    Return a JSON object with exactly these keys:
    - "recommendation": "recommend" | "borderline" | "reject"
    - "score": a number from 0 to 10 (one decimal place) reflecting overall candidate quality — holistic assessment including communication, depth, and impression
    - "summary": 1-2 sentences maximum — candidate's key strength and the decisive factor for the recommendation. No filler.
    - "structured_feedback": an object with:
        - "strengths": array of strings (3-5 points) — specific, evidence-based positive signals from the transcript that do not appear in jd_requirements_coverage
        - "communication_quality": "poor" | "fair" | "good" | "excellent"
        - "cv_interview_consistency": "consistent" | "minor inconsistencies" | "significant inconsistencies"
        - "jd_requirements_coverage": array of objects, one per must-have JD requirement, each with:
            - "requirement": the must-have requirement as stated or closely paraphrased from the JD
            - "coverage": "addressed" | "partial" | "not addressed"
                - "addressed": candidate gave a substantive, specific, real-world example or demonstrated clear hands-on knowledge directly relevant to this requirement
                - "partial": candidate referenced the area but provided only surface-level, generic, or incomplete evidence — or demonstrated adjacent but not direct experience
                - "not addressed": candidate did not demonstrate this requirement in the interview
            - "evidence": one sentence — what the candidate said (or failed to say) that drove this rating; quote directly from the transcript where possible
        - "episode_dimensions": an object scoring the candidate's overall interview performance across five behavioural dimensions. Each dimension is assessed holistically across the full transcript — not per question. Use "meets" | "partially_meets" | "vague" | "does_not_meet" for every dimension.
            - "relevance_discipline":
                - "meets": laser-focused; every sentence directly answers the prompt with zero rambling
                - "partially_meets": minor tangential details, but the core answer remains on point
                - "vague": heavy background context or narrative fluff; substance is light
                - "does_not_meet": scattered answer that wanders completely away from the core question
            - "ownership_language":
                - "meets": flawless first-person active grammar throughout ("I designed," "I led")
                - "partially_meets": balanced mix of I and we, with personal contributions clearly defined
                - "vague": diffused we-language; highly unclear what they personally drove
                - "does_not_meet": zero personal ownership claimed; acted entirely as a passive observer
            - "outcome_orientation":
                - "meets": voluntarily leads with hard data, technical metrics, or clear business results
                - "partially_meets": mentioned results/deltas only when explicitly prompted or naturally arising
                - "vague": activity-focused; described what they did step-by-step with no results stated
                - "does_not_meet": effort-focused; framed answers around how hard they worked, not what happened
            - "adaptability_signal":
                - "meets": explicitly detailed an active strategy pivot when project constraints changed
                - "partially_meets": showed strong awareness of alternative approaches, but didn't execute them
                - "vague": fixed mindset; described using the exact same playbook across all examples
                - "does_not_meet": rigid mindset; actively resisted or dismissed the idea that context alters approach
            - "communication_clarity":
                - "meets": sentences are logically structured and technically coherent; zero effort to parse
                - "partially_meets": understandable, but heavily relies on crutch words ("like," "um," "you know")
                - "vague": highly fragmented thoughts; structure disrupts the technical meaning
                - "does_not_meet": complete word-salad; technical explanation is entirely incomprehensible
        - "domain_drift": true | false — whether the candidate shifted answers toward a different domain (e.g. general IT support, web development, project coordination, helpdesk) when asked role-specific questions
        - "domain_drift_explanation": a 1-sentence description of what domain the answers drifted toward and in which questions; null if domain_drift is false
    - "red_flags": array of strings — operational, credibility, or risk-weight flags only; must not duplicate jd_requirements_coverage gaps; empty array if none
    - "decision_rationale": a 1-2 sentence explanation of the recommendation

    Return only valid JSON. No markdown fences, no extra text.
  PROMPT

  def initialize(analysis)
    @analysis = analysis
    @client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def call
    @analysis.transition_to!("analyzing")
    raise "No transcript available" if @analysis.transcript.blank?

    transcript   = @analysis.cleaned_transcript.presence || @analysis.transcript
    job_context  = @analysis.job_role.to_prompt

    response = @client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      temperature: 0,
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: build_user_message(transcript, job_context) }]
    )

    raw_json = response.content.first.text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    result = JSON.parse(raw_json)

    # Compute jd_fit_score server-side from qualitative coverage labels — never trust Claude's arithmetic.
    jd_cov = Array(result.dig("structured_feedback", "jd_requirements_coverage"))
    jd_n_addr = jd_cov.count { |r| r["coverage"] == "addressed" }
    jd_n_par  = jd_cov.count { |r| r["coverage"] == "partial" }
    jd_n_tot  = jd_cov.size
    jd_fit_score = jd_n_tot > 0 ? ((jd_n_addr * 1.0 + jd_n_par * 0.5) / jd_n_tot * 10.0).round(1) : nil

    @analysis.update!(
      score: result["score"],
      summary: result["summary"],
      structured_feedback: result["structured_feedback"].merge(
        "recommendation"            => result["recommendation"],
        "jd_fit_score"              => jd_fit_score,
        "red_flags"                 => result["red_flags"],
        "decision_rationale"        => result["decision_rationale"]
      ),
      prompt_version: PROMPT_VERSION,
      status: "completed"
    )

    result
  rescue JSON::ParserError => e
    raise "Claude returned invalid JSON: #{e.message}"
  end

  private

  def calibration_note
    case @analysis.job_role&.experience_level
    when "junior"
      "Calibration note: This is a junior-level role. Prioritise learning attitude, foundational knowledge, and coachability. Do not penalise for lack of advanced experience."
    when "mid"
      "Calibration note: This is a mid-level role. Expect clear evidence of independent delivery and hands-on competence. The candidate should demonstrate they can operate without close supervision but is not yet expected to lead strategy or mentor others."
    when "senior"
      "Calibration note: This is a senior-level role. Expect concrete examples of ownership, complex problem-solving, and influence beyond individual contributions."
    when "executive"
      "Calibration note: This is an executive-level role. Assess strategic thinking, organisational impact, and cross-functional leadership."
    end
  end

  def candidate
    @candidate ||= Candidate.find_by(video_analysis_id: @analysis.id)
  end

  def cv_screening_context
    cv = candidate&.cv_analysis
    return nil unless cv&.structured_feedback.present? && cv.score.present?

    fb = cv.structured_feedback
    lines = []
    lines << "CV Fit Score: #{fb['cv_fit_score']}/10 (formula-derived) · CV Score: #{cv.score}/10 (holistic)" if fb["cv_fit_score"].present?
    lines << "CV Recommendation: #{fb['recommendation']}" if fb["recommendation"].present?
    lines << "Decision rationale: #{fb['decision_rationale']}" if fb["decision_rationale"].present?

    cov = Array(fb["cv_requirements_coverage"])
    if cov.any?
      lines << "\nMust-have requirements from CV screening (use interview to probe partials and gaps):"
      cov.each do |r|
        tag = case r["coverage"]
              when "evidenced"     then "evidenced"
              when "partial"       then "partial  "
              when "not evidenced" then "missing  "
              else                      "unknown  "
              end
        line = "  #{tag} | #{r['requirement']}"
        line += " — #{r['evidence']}" if r["evidence"].present?
        lines << line
      end
    else
      # fallback for legacy records without structured coverage
      if fb["matched_skills"].present?
        lines << "\nMust-have requirements evidenced in CV:\n" +
                 Array(fb["matched_skills"]).map { |s| "- #{s}" }.join("\n")
      end
      if fb["missing_skills"].present?
        lines << "\nMust-have requirements absent from CV:\n" +
                 Array(fb["missing_skills"]).map { |s| "- #{s}" }.join("\n")
      end
    end

    if fb["skill_evidence_gaps"].present?
      lines << "\nSkills listed on CV with no role-level evidence (watch whether the interview provides it):\n" +
               Array(fb["skill_evidence_gaps"]).map { |s| "- #{s}" }.join("\n")
    end

    if fb["credential_flags"].present?
      lines << "\nCredential or consistency flags raised during CV screening:\n" +
               Array(fb["credential_flags"]).map { |s| "- #{s}" }.join("\n")
    end

    nh_cov = Array(fb["nice_to_have_requirements_coverage"])
    if nh_cov.any?
      lines << "\nNice-to-have requirements from CV screening (interview can confirm or deepen partials and fill missing):"
      nh_cov.each do |r|
        tag  = { "evidenced" => "evidenced", "partial" => "partial  ", "not evidenced" => "missing  " }[r["coverage"]] || "unknown  "
        line = "  #{tag} | #{r['requirement']}"
        line += " — #{r['evidence']}" if r["evidence"].present?
        lines << line
      end
    end

    lines << "\nRole balance observation: #{fb['role_balance_fit']}" if fb["role_balance_fit"].present?

    must_ask = Array(fb["interview_questions"]).select { |q| q["priority"] == "must ask" }
    if must_ask.any?
      lines << "\nMust-ask questions from CV screening (note whether each was addressed, evaded, or not raised):\n" +
               must_ask.each_with_index.map { |q, i| "#{i + 1}. [#{q['focus']}] #{q['question']}" }.join("\n")
    end

    lines.join("\n")
  end

  def pool_context
    role = @analysis.job_role
    return nil unless role

    pool = VideoAnalysis.joins(:job_role)
                        .where(job_role: role, status: "completed")
                        .where.not(id: @analysis.id)
                        .where.not(score: nil)

    return nil if pool.empty?

    all_scores = pool.map { |va| va.score.to_f }
    all_jd     = pool.filter_map { |va| va.structured_feedback&.dig("jd_fit_score")&.to_f }

    lines = ["Score range across all #{pool.count} completed interview#{"s" if pool.count != 1} for this role:"]
    lines << "  Score — min: #{all_scores.min}, max: #{all_scores.max}, avg: #{(all_scores.sum / all_scores.size).round(1)}"
    lines << "  JD fit — min: #{all_jd.min}, max: #{all_jd.max}, avg: #{(all_jd.sum / all_jd.size).round(1)}" if all_jd.any?
    lines << "Use these ranges to calibrate scores relative to the full candidate pool."

    lines.join("\n")
  end

  def build_user_message(transcript, job_context)
    parts = []
    parts << calibration_note if calibration_note
    parts << "## Job Requirements\n#{job_context}"
    if @analysis.job_role&.requirements_locked?
      parts << "## Scoring Constraint\nThe Must-Have Requirements list above is canonical and locked. " \
               "Your jd_requirements_coverage array MUST contain exactly one entry per requirement, " \
               "in the same order, using the exact wording provided. Do not add, merge, split, or omit any requirement."
    end
    parts << "## Historical Outcomes for This Role\n#{outcome_examples_context}" if outcome_examples_context
    parts << "## Prior CV Screening\n#{cv_screening_context}" if cv_screening_context
    parts << "## Candidate Pool Context\n#{pool_context}" if pool_context
    parts << "## Interview Transcript\n#{transcript}"
    parts.join("\n\n")
  end

  def outcome_examples_context
    return @_outcome_examples_context if defined?(@_outcome_examples_context)
    @_outcome_examples_context = build_outcome_examples_context
  end

  def build_outcome_examples_context
    role = @analysis.job_role
    return nil unless role

    examples = Candidate
      .where(job_role: role, pipeline_stage: %w[final_interview not_invited])
      .where.not(outcome_confirmed_at: nil)
      .where.not(id: candidate&.id)
      .order(outcome_confirmed_at: :desc)
      .includes(:video_analysis)
      .limit(6)

    return nil if examples.empty?

    invited     = examples.select { |c| c.pipeline_stage == "final_interview" }
    not_invited = examples.select { |c| c.pipeline_stage == "not_invited" }

    lines = [
      "Anonymised outcomes from past interviews for this role, confirmed by the recruiter.",
      "Use these to calibrate how the hiring team distinguishes strong from weak interview performance."
    ]

    if invited.any?
      lines << "\n### Invited to Final Interview"
      invited.first(3).each_with_index do |c, i|
        lines << format_interview_outcome_example(c, i + 1)
      end
    end

    if not_invited.any?
      lines << "\n### Not Invited to Final Interview"
      not_invited.first(3).each_with_index do |c, i|
        lines << format_interview_outcome_example(c, i + 1)
      end
    end

    lines.join("\n")
  end

  def format_interview_outcome_example(candidate, index)
    va = candidate.video_analysis
    return nil unless va&.structured_feedback.present? && va.score.present?

    fb   = va.structured_feedback
    jd   = fb["jd_fit_score"]
    ep   = va.episode_score
    dims = fb["episode_dimensions"] || {}

    score_line = []
    score_line << "Episode Score: #{ep}/10" if ep.present?
    score_line << "holistic: #{va.score}/10"
    score_line << "JD fit: #{jd}/10" if jd.present?

    lines = []
    lines << "\nExample #{index} (#{score_line.join(' · ')}):"

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
    lines << "  CV-interview consistency: #{fb['cv_interview_consistency']}"         if fb["cv_interview_consistency"].present?
    lines << "  Red flags: #{Array(fb['red_flags']).first(2).join('; ')}"            if fb["red_flags"].present?
    lines << "  Rationale: #{fb['decision_rationale']}"                              if fb["decision_rationale"].present?
    lines << "  Recruiter note: #{candidate.outcome_note}"                           if candidate.outcome_note.present?

    lines.join("\n")
  end
end
