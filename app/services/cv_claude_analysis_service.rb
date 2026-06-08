require "anthropic"

class CvClaudeAnalysisService
  MODEL          = "claude-sonnet-4-6"
  PROMPT_VERSION = "2026-06-08-v8"

  SYSTEM_PROMPT = <<~PROMPT
    You are an expert recruiter evaluating a candidate's CV against a job description.

    Your goal is to assess whether the candidate's documented skills and experience are a strong enough match to proceed to a preliminary interview.

    When reading the job description, distinguish between must-have requirements and preferred or bonus requirements. Weight must-have requirements heavily in the score. Preferred requirements should improve the score but their absence alone should not trigger a reject.

    Where the role has a hybrid or multi-disciplinary structure (e.g., a mix of two functions, disciplines, or responsibility types), assess whether the CV demonstrates both sides in actual work history — not just in a skills list. Read the JD to determine what the relevant balance dimensions are for this specific role before making that assessment.

    Practical, hands-on project experience and credentials are both valid signals. Neither is inherently more important than the other — weight them according to what the JD emphasizes. Observe how the CV is anchored without treating one approach as superior.

    When an Experience Level is specified for the role:
    - Junior: Prioritise demonstrated willingness to learn, foundational knowledge, and early-career evidence of growth. Do not penalise for limited years of experience. Credential flags and evidence gaps are expected at this level — weight them less heavily unless they directly contradict a must-have requirement.
    - Senior: Expect clear evidence of ownership, complex problem-solving, and results beyond task execution. Thin evidence on must-have requirements is a stronger concern at this level than at junior.
    - Executive: Assess strategic scope, cross-functional influence, and leadership of significant initiatives. Individual contributor evidence alone is insufficient.

    When Historical Outcomes are provided:
    - These are real hiring decisions made by the client for this specific role, confirmed by the recruiter.
    - Use them to calibrate your scoring threshold — if invited examples share a pattern (e.g. strong evidence in a particular area, meeting a skill threshold), treat that pattern as a validated signal for this role.
    - If not-invited examples share a pattern (e.g. a missing skill, a credential flag, a weak role balance fit, a concerning career progression), treat that as a confirmed disqualifier.
    - If a recruiter note is attached to an example, treat it as direct client feedback about what mattered most for that decision.
    - Do not mechanically replicate scores. The examples are directional guides, not ceilings or floors.
    - If the current candidate is genuinely stronger or weaker than any example, score accordingly and note it in decision_rationale.

    Flag any of the following:
    - Claimed experience or qualifications that appear implausible or inconsistent with the overall CV narrative
    - Significant unexplained employment gaps or lateral moves
    - Skills or qualifications listed in a skills section that have no supporting evidence in any role description

    Return a JSON object with exactly these keys:
    - "recommendation": "recommend" | "borderline" | "reject"
    - "score": a number from 0 to 10 (one decimal place) reflecting overall CV-to-JD fit — holistic assessment including career progression, credential signals, and experience anchoring
    - "summary": 1-2 sentences maximum — candidate's key CV strength and the decisive factor for the recommendation. No filler.
    - "structured_feedback": an object with:
        - "cv_requirements_coverage": array of objects, one per must-have JD requirement, each with:
            - "requirement": the must-have requirement as stated or closely paraphrased from the JD
            - "reasoning": one sentence — state what you found or did not find in the CV before committing to a coverage rating
            - "coverage": "evidenced" | "partial" | "not evidenced"
                - "evidenced" (1.0): Direct, explicit alignment. The CV explicitly names the tool, framework, or core competency. Location in the CV (role description or skills list) does not affect this rating — explicit naming is the only criterion.
                  Example — JD requires Git and CI/CD: CV states "Managed version control via GitHub and built automated CI/CD deployment pipelines." → evidenced.
                - "partial" (0.5): Implied or high-level functional proximity. The exact tool or specific keyword is absent, but an adjacent technology, highly transferable skill, or overarching conceptual capability is clearly stated.
                  Example — JD requires Git and CI/CD: CV states "Handled code deployments and team code reviews using Workbench." → partial (deployments present, explicit Git/CI/CD tool absent).
                - "not evidenced" (0.0): Absolute silence. Zero structural, conceptual, or keyword-based evidence relating to this requirement anywhere in the CV.
                  Example — JD requires Git and CI/CD: CV mentions only individual code writing with no reference to teams, tools, deployments, or version control. → not evidenced.
            - "evidence": one sentence from the CV that drove this rating, or what is absent
        - "nice_to_have_requirements_coverage": array of objects, one per nice-to-have requirement (use exact wording from the list provided), each with:
            - "requirement": the nice-to-have requirement exactly as stated
            - "coverage": "evidenced" | "partial" | "not evidenced" — same definitions as cv_requirements_coverage
            - "evidence": one sentence from the CV that drove this rating, or what is absent
        - "matched_skills": array of strings — must-have JD requirements evidenced in the CV, with role-description evidence where possible
        - "missing_skills": array of strings — must-have JD requirements absent from the CV
        - "preferred_skills_present": array of strings — bonus or preferred JD requirements the candidate does have; empty array if none
        - "skill_evidence_gaps": array of strings — must-have JD requirements that the candidate lists in a skills section but never demonstrates in any role description; empty array if none. Do NOT include skills that are not required by the JD — only flag gaps that are directly relevant to this role.
        - "experience_anchoring": "primarily hands-on project experience" | "mix of experience and credentials" | "primarily credentials and titles" — a neutral observation of how the CV demonstrates capability, not a judgment of quality
        - "role_balance_fit": a short free-text observation (1-2 sentences) describing how well the candidate's documented experience reflects the balance of responsibilities described in the JD — using the JD's own terms for what those dimensions are
        - "career_progression": "strong" | "steady" | "concerning" — based on trajectory, gaps, or unexplained moves
        - "credential_flags": array of strings — qualifications or claims that seem implausible or inconsistent with the rest of the CV; empty array if none
        - "experience_level_fit": "below requirements" | "meets requirements" | "exceeds requirements"
        - "cv_fit_score_raw": omit this field — the server computes it from cv_requirements_coverage
        - "cv_fit_adjustments": omit this field — the server derives it from your qualitative signal fields below
        - "career_trajectory_alignment": "toward_role" | "lateral" | "away_from_role"
            - "toward_role": each recent role builds progressively toward this type of position; most recent role is the closest match to the JD
            - "lateral": roles show similar level across different functions without clear progression toward this role
            - "away_from_role": career has moved away from the relevant experience — more relevant work is buried in older roles
        - "career_trajectory_alignment_note": comma-separated phrases naming the specific roles or transitions that drove this rating — factual, no prose (e.g. "Bootcamp → developer → consultant → embedded role, clear compounding progression")
        - "industry_proximity": "direct" | "adjacent" | "transferable" | "none"
            - "direct": same industry as the role
            - "adjacent": different industry but same buyer type, deal size, or complexity level
            - "transferable": different industry but core responsibilities map cleanly to JD requirements
            - "none": no meaningful industry overlap
        - "industry_proximity_note": comma-separated phrases naming the specific employer(s) or experience that drove this rating — factual, no prose
        - "scope_indicators": an object with inferred scale signals even when not explicitly stated:
            - "account_size": "enterprise" | "mid_market" | "smb" | "unknown" — inferred from company size, client names, or deal context
            - "team_context": "manager" | "lead" | "individual_contributor" | "unknown" — inferred from titles and responsibilities
            - "geography": "international" | "regional" | "local" | "unknown"
            - "scope_note": one sentence describing how scope was inferred and at what level the candidate has operated
            - "scope_match": "strong_match" | "partial_match" | "no_match" — whether the candidate's scope of experience fits the scale requirements of THIS role. Read the JD to determine the target scope (e.g. enterprise, SMB, regional) before rating. A candidate whose scope exceeds or falls short of what the role requires should not receive strong_match.
        - "tenure_pattern": "sufficient" | "short_in_relevant_roles"
            - "sufficient": candidate stayed 12+ months in roles directly relevant to the JD, or relevant roles are the current position
            - "short_in_relevant_roles": pattern of less than 12 months in roles directly relevant to the JD — raises a depth concern
        - "tenure_pattern_note": comma-separated role + duration pairs (e.g. "Simplus ~24 months, TruDiagnostic ~9 months and growing, Collabera ~13 months")
        - "responsibility_density": "high" | "medium" | "low"
            - "high": majority of role description content maps to JD responsibilities
            - "medium": some relevant content among mixed responsibilities
            - "low": one or two relevant points buried in unrelated content
        - "responsibility_density_note": comma-separated list of the specific responsibilities from the most relevant role that map to JD requirements (e.g. "Apex classes, batch processes, REST/SOAP APIs, Agile delivery")
        - "recency_of_relevant_experience": "current" | "within_3_years" | "older_than_3_years"
            - "current": most relevant experience is in the current or most recent role
            - "within_3_years": most relevant experience is within the last 3 years but not in the most recent role
            - "older_than_3_years": most relevant experience is only in roles older than 3 years
        - "recency_of_relevant_experience_note": the most relevant role and its approximate dates — factual, comma-separated if multiple (e.g. "Current role at Simplus, active Salesforce architecture work")
        - "implied_competency_from_employer": "strongly_implied" | "consistent" | "no_signal"
            - "strongly_implied": the employer's known profile almost certainly required the candidate to perform the JD's key responsibilities — award partial credit even without explicit CV statement
            - "consistent": employer context is consistent with having the required experience but does not specifically imply it
            - "no_signal": employer context provides no meaningful inference about required competencies
        - "implied_competency_from_employer_note": employer name + what their known profile implies — comma-separated, no prose (e.g. "Simplus is a Salesforce consulting partner — multi-client delivery, Apex best practices, integration patterns strongly implied")
        - "tool_specificity": integer 1–10 — how specifically the CV names tools, platforms, and technologies. 1 = only generic mentions ("Salesforce", "cloud tools"); 10 = specific named features, modules, and integrations backed by role-level evidence throughout
        - "ownership_clarity": integer 1–10 — how clearly the CV distinguishes direct ownership from peripheral involvement. 1 = all vague language ("worked with", "exposure to", "involved in"); 10 = clear first-person ownership throughout ("built", "owned", "designed", "led delivery of")
        - "quantifiable_work": integer 1–10 — presence of specific, measurable project work. 1 = no numbers, project names, or outcomes anywhere; 10 = multiple specific projects with named outcomes, org sizes, user counts, or impact metrics
        - "interview_questions": array of 3-5 objects, each with:
            - "question": an open-ended, behavioural interview question the recruiter should ask
            - "focus": one of "gap in must-have" | "validate claimed experience" | "skill evidence gap"
            - "reason": one sentence explaining what this question is trying to surface or confirm
            - "priority": "must ask" | "if time allows"
                - "must ask": assign this when focus is "gap in must-have" OR when focus is "skill evidence gap" for a skill the JD explicitly requires; these questions address gaps that will directly affect the recommendation if left unanswered
                - "if time allows": assign this when focus is "validate claimed experience" or when the skill evidence gap is for a preferred (non-must-have) skill
    - "decision_rationale": a 1-2 sentence explanation of why this recommendation was made

    Interview questions must:
    - Be specific to this candidate's CV and this JD — not generic HR questions
    - Be phrased so the candidate can answer with a concrete story or example
    - Focus entirely on gaps and unsubstantiated claims — do not include "validate claimed experience" questions for requirements already marked "evidenced" in cv_requirements_coverage
    - Only use focus "validate claimed experience" for requirements marked "partial" in cv_requirements_coverage, where the claim exists but lacks role-level evidence
    - Assign "must ask" to every question with focus "gap in must-have" and to "skill evidence gap" questions for JD-required skills; assign "if time allows" to "validate claimed experience" questions

    Return only valid JSON. No markdown fences, no extra text.
  PROMPT



  def initialize(analysis)
    @analysis = analysis
    @client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def call
    @analysis.transition_to!("analyzing")
    raise "No CV text available" if @analysis.extracted_text.blank?

    job_context = @analysis.job_role.to_prompt

    response = @client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      temperature: 0,
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" }
        }
      ],
      messages: [
        {
          role: "user",
          content: build_user_content(job_context)
        }
      ]
    )

    raw_json = response.content.first.text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    result = JSON.parse(raw_json)

    sf = result["structured_feedback"] || {}

    # Server always owns cv_fit_score — recompute raw and adjustments from Claude's
    # qualitative outputs, never trusting Claude's arithmetic.
    reqs_cov = Array(sf["cv_requirements_coverage"])
    n_ev  = reqs_cov.count { |r| r["coverage"] == "evidenced" }
    n_par = reqs_cov.count { |r| r["coverage"] == "partial" }
    n_tot = reqs_cov.size
    raw = n_tot > 0 ? ((n_ev * 1.0 + n_par * 0.5) / n_tot * 7.0).round(2) : 0.0
    sf["cv_fit_score_raw"] = raw

    adjs = recompute_adjustments(sf)
    sf["cv_fit_adjustments"] = adjs
    adjs_total = adjs.values.sum

    nh_coverage = Array(sf["nice_to_have_requirements_coverage"])
    nh_bonus = nh_coverage.sum do |r|
      case r["coverage"]
      when "evidenced" then 0.5
      when "partial"   then 0.25
      else 0.0
      end
    end
    nh_bonus = [nh_bonus, 1.5].min.round(2)
    sf["nice_to_have_bonus"] = nh_bonus

    result["cv_fit_score"] = [[raw + adjs_total + nh_bonus, 10.0].min, 0.0].max.round(1)

    @analysis.update!(
      score: result["score"],
      summary: result["summary"],
      structured_feedback: result["structured_feedback"].merge(
        "recommendation"     => result["recommendation"],
        "cv_fit_score"       => result["cv_fit_score"],
        "decision_rationale" => result["decision_rationale"]
      ),
      prompt_version: PROMPT_VERSION,
      status: "completed"
    )

    result
  rescue JSON::ParserError => e
    raise "Claude returned invalid JSON: #{e.message}"
  end

  private

  def cv_pool_context
    role = @analysis.job_role
    return nil unless role

    pool = CvAnalysis.where(job_role: role, status: "completed")
                     .where.not(id: @analysis.id)

    return nil if pool.empty?

    scores = pool.filter_map(&:cv_fit_score).map(&:to_f)
    return nil if scores.empty?

    tiers = pool.filter_map(&:cv_fit_tier)
    tier_counts = tiers.tally

    lines = ["CV Fit Score range across #{pool.count} completed CV screening#{"s" if pool.count != 1} for this role:"]
    lines << "  min: #{scores.min}, max: #{scores.max}, avg: #{(scores.sum / scores.size).round(1)}"
    if tier_counts.any?
      lines << "  Tier breakdown: " + tier_counts.map { |t, n| "#{t} #{n}" }.join(", ")
    end
    lines << "Use these to calibrate scores relative to the full candidate pool for this role."
    lines.join("\n")
  end

  def recompute_adjustments(sf)
    scope_bonus = case sf.dig("scope_indicators", "scope_match")
                  when "strong_match"   then 0.50
                  when "partial_match"  then 0.25
                  else 0.00
                  end

    {
      "trajectory_bonus" => case sf["career_trajectory_alignment"]
                            when "toward_role" then 0.50
                            when "lateral"     then 0.25
                            else 0.00
                            end,
      "scope_bonus"      => scope_bonus,
      "recency_bonus"    => case sf["recency_of_relevant_experience"]
                            when "current"        then 0.50
                            when "within_3_years" then 0.25
                            else 0.00
                            end,
      "implied_competency_bonus" => case sf["implied_competency_from_employer"]
                                    when "strongly_implied" then 0.50
                                    when "consistent"       then 0.25
                                    else 0.00
                                    end,
      "tenure_bonus"     => sf["tenure_pattern"] == "sufficient" ? 0.50 : 0.00,
      "density_bonus"    => case sf["responsibility_density"]
                            when "high"   then 0.50
                            when "medium" then 0.25
                            else 0.00
                            end
    }
  end

  def build_user_content(job_context)
    parts = [
      {
        type: "text",
        text: "## Job Requirements\n#{job_context}",
        cache_control: { type: "ephemeral" }
      }
    ]
    if @analysis.job_role&.requirements_locked?
      parts << {
        type: "text",
        text: "## Scoring Constraint\nThe Must-Have Requirements list above is canonical and locked. " \
              "Your cv_requirements_coverage array MUST contain exactly one entry per requirement, " \
              "in the same order, using the exact wording provided. Do not add, merge, split, or omit any requirement."
      }
    end
    parts << { type: "text", text: "## Experience Level\n#{experience_level_context}" } if experience_level_context
    parts << { type: "text", text: "## Candidate Pool Context\n#{cv_pool_context}" } if cv_pool_context
    parts << { type: "text", text: "## Historical Outcomes for This Role\n#{outcome_examples_context}" } if outcome_examples_context
    parts << { type: "text", text: "## Candidate CV\n#{@analysis.extracted_text}" }
    parts
  end

  def experience_level_context
    case @analysis.job_role&.experience_level
    when "junior"    then "Junior-level role. Apply junior calibration when scoring."
    when "mid"       then "Mid-level role. Expect independent delivery and hands-on competence without close supervision. Not yet expected to lead strategy or mentor others."
    when "senior"    then "Senior-level role. Apply senior calibration when scoring."
    when "executive" then "Executive-level role. Apply executive calibration when scoring."
    end
  end

  def outcome_examples_context
    return nil unless @analysis.job_role

    examples = Candidate
      .where(job_role: @analysis.job_role, pipeline_stage: %w[final_interview not_invited])
      .where.not(outcome_confirmed_at: nil)
      .order(outcome_confirmed_at: :desc)
      .includes(:cv_analysis)
      .limit(6)

    return nil if examples.empty?

    invited     = examples.select { |c| c.pipeline_stage == "final_interview" }
    not_invited = examples.select { |c| c.pipeline_stage == "not_invited" }

    lines = [
      "Anonymised outcomes from past CV screenings for this role, confirmed by the recruiter.",
      "Use these as calibration examples — they represent what the hiring team has validated as strong vs. weak CV fits."
    ]

    if invited.any?
      lines << "\n### Invited to Final Interview"
      invited.first(3).each_with_index do |c, i|
        lines << format_cv_outcome_example(c, i + 1)
      end
    end

    if not_invited.any?
      lines << "\n### Not Invited to Final Interview"
      not_invited.first(3).each_with_index do |c, i|
        lines << format_cv_outcome_example(c, i + 1)
      end
    end

    lines.join("\n")
  end

  def format_cv_outcome_example(candidate, index)
    cv = candidate.cv_analysis
    return nil unless cv&.structured_feedback.present? && cv.score.present?

    fb    = cv.structured_feedback
    lines = []
    score_line = "CV Fit Score: #{fb['cv_fit_score']}/10" if fb["cv_fit_score"].present?
    score_line = [score_line, "holistic: #{cv.score}/10"].compact.join(" · ")
    lines << "\nExample #{index} (#{score_line}, recommendation: #{fb['recommendation']}):"

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
      lines << "  Matched must-haves: #{Array(fb['matched_skills']).first(4).join(', ')}"  if fb["matched_skills"].present?
      lines << "  Missing must-haves: #{Array(fb['missing_skills']).first(3).join(', ')}"  if fb["missing_skills"].present?
    end

    lines << "  Evidence gaps: #{Array(fb['skill_evidence_gaps']).first(2).join(', ')}"    if fb["skill_evidence_gaps"].present?
    lines << "  Career progression: #{fb['career_progression']}"                           if fb["career_progression"].present?
    lines << "  Experience level fit: #{fb['experience_level_fit']}"                       if fb["experience_level_fit"].present?
    lines << "  Rationale: #{fb['decision_rationale']}"                                    if fb["decision_rationale"].present?
    lines << "  Recruiter note: #{candidate.outcome_note}"                                 if candidate.outcome_note.present?

    lines.join("\n")
  end
end
