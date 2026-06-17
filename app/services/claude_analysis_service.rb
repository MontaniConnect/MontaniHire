class ClaudeAnalysisService
  MODEL          = "claude-sonnet-4-6"
  PROMPT_VERSION = "2026-06-17-v9"

  SYSTEM_PROMPT = <<~PROMPT
    You are an expert HR analyst evaluating a candidate's preliminary interview transcript against a specific job role.

    Your goal is to give a recruiter an independent, honest signal about candidate quality before the candidate is presented to the client. The recruiter is not a technical expert, so your assessment must be clear and actionable.

    You have access to the candidate's CV and, where available, the results of a prior CV screening. Use both to assess consistency, but also to detect gaps between what the CV promises and what the interview actually delivered.

    When a Prior CV Screening is provided:
    - Treat missing must-have requirements as open questions that the interview must answer. If the interview does not address them, that absence should lower the score.
    - Treat skill evidence gaps as hypotheses to test: did the candidate demonstrate those skills in the interview, or do they remain unsubstantiated?
    - Do not simply re-score the CV. The interview is an independent signal. A weak CV can be partially redeemed by a strong interview, and a strong CV can be undermined by a poor one.
    - If targeted interview questions are listed, note in strengths or red_flags whether gaps were addressed or evaded — do not flag gaps that were simply not raised by the interviewer.

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
    - "recommendation": "comprehensive" | "substantive" | "superficial"
    - "score": a number from 0 to 10 (one decimal place) reflecting overall candidate quality — holistic assessment including communication, depth, and impression
    - "summary": 1-2 sentences maximum. Must contain exactly two elements:
        (1) Key Strength: a highly specific, data-driven behavioural spike or culture add grounded in transcript evidence — not generic praise (e.g. "demonstrated strong pattern recognition by working backward from a failed project", not "great communicator")
        (2) Core Weakness / Decisive Factor: a real, unmasked friction point or growth area linked to a specific self-awareness signal, unguarded moment, or red flag in the interview (e.g. "was subtly dismissive during scheduling", "lacks deep Python experience but is proactively taking a course") — no ruinous empathy, no fake weaknesses like "perfectionism"
        Zero filler words. No praise-padding before the weakness.
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
        - "episode_dimensions": an object scoring the candidate's overall interview performance across five behavioural dimensions. Each dimension is assessed holistically across the full transcript — not per question. Each dimension value is an object with exactly three keys: "literal_quote", "tier_check", and "rating".
            - "relevance_discipline": an object with:
                - "literal_quote": copy the exact phrase from the transcript that most directly drove the rating. Write "NONE" if no explicit phrase supports it.
                - "tier_check": (Weight: 20%) Measures cognitive focus and the ability to listen and directly address a prompt. State which tier definition the evidence matches and why, including any close-call consideration:
                    - "meets": The candidate actively listens, addresses the exact prompt within the first 30 seconds, and concludes their thought cleanly without prompts.
                    - "partially_meets": Answers the question but takes a scenic route — includes slightly unrelated background context before hitting the point.
                    - "vague": Speaks in high-level theories or generalisations about the topic rather than sharing a specific, disciplined story.
                    - "does_not_meet": Completely hijacks the question to deliver a pre-memorised script, or rambles continuously until interrupted by the interviewer.
                - "rating": "meets" | "partially_meets" | "vague" | "does_not_meet"
            - "ownership_language": an object with:
                - "literal_quote": copy the exact phrase from the transcript that most directly drove the rating. Write "NONE" if no explicit phrase supports it.
                - "tier_check": (Weight: 10%) Measures personal accountability while filtering out political corporate camouflage. State which tier definition the evidence matches and why, including any close-call consideration:
                    - "meets": Explicitly uses "I" to define their personal scope, decisions, and mistakes, while naturally using "we" only to attribute shared success or team morale.
                    - "partially_meets": Uses "we" for everything initially, but when explicitly prompted ("What was your exact role?"), they can quickly isolate their individual contribution.
                    - "vague": The transcript is heavily passive (e.g., "The project was launched," or "I was part of the circle that oversaw…"). Individual footprint is highly blurred.
                    - "does_not_meet": Credit-hogging (taking 100% solo credit for a massive multi-team effort) OR absolute deflection (using "we" as a shield to disguise the fact that they didn't actually execute any core tasks).
                - "rating": "meets" | "partially_meets" | "vague" | "does_not_meet"
            - "outcome_orientation": an object with:
                - "literal_quote": copy the exact phrase from the transcript that most directly drove the rating. Write "NONE" if no explicit phrase supports it.
                - "tier_check": (Weight: 30%) Measures whether the candidate is driven by business reality or just passing time. State which tier definition the evidence matches and why, including any close-call consideration:
                    - "meets": Automatically anchors their story around a metric or a clear definition of success. Delivers the "R" in the STAR method without being asked.
                    - "partially_meets": Mentions a successful outcome, but it is purely qualitative (e.g., "The client was very happy"), or needs to be explicitly nudged to provide a data point.
                    - "vague": Describes a mountain of tasks, meetings, and personal busyness, but never clearly connects that activity to a final organisational result.
                    - "does_not_meet": Tells a story where the project dragged on indefinitely, failed without any reflection, or had no measurable purpose to begin with.
                - "rating": "meets" | "partially_meets" | "vague" | "does_not_meet"
            - "adaptability_signal": an object with:
                - "literal_quote": copy the exact phrase from the transcript that most directly drove the rating. Write "NONE" if no explicit phrase supports it.
                - "tier_check": (Weight: 25%) Identifies learning agility and lack of ego. State which tier definition the evidence matches and why, including any close-call consideration:
                    - "meets": Describes a moment where their initial plan failed or constraints suddenly changed. Explicitly outlines how they shifted mindset, gathered feedback, and changed tactics.
                    - "partially_meets": Pivoted because they were forced to by management or external circumstances, rather than showing proactive situational awareness.
                    - "vague": Acknowledges a challenge occurred, but glosses over how they adapted — simply asserting they "worked harder" or "figured it out."
                    - "does_not_meet": Pure rigidity. When a playbook failed, they doubled down on the broken strategy, blamed external factors, or refused to accept candid feedback.
                - "rating": "meets" | "partially_meets" | "vague" | "does_not_meet"
            - "communication_clarity": an object with:
                - "literal_quote": copy the exact phrase from the transcript that most directly drove the rating. Write "NONE" if no explicit phrase supports it.
                - "tier_check": (Weight: 15%) Measures structured thinking, narrative architecture, and baseline executive presence. State which tier definition the evidence matches and why, including any close-call consideration:
                    - "meets": Exceptional structural hygiene. Uses signposting (e.g., "There were two main challenges here; first…") or follows a crisp chronological path.
                    - "partially_meets": The story is fully coherent and easy to follow, but lacks crisp structure — reads more like a casual, unstructured chat.
                    - "vague": Fragmented pacing. Jumps backward and forward in time, forcing the interviewer to do mental gymnastics to piece the timeline together.
                    - "does_not_meet": Word salad. Deeply disorganised thoughts, heavy technical jargon used incorrectly to mask confusion, or answers that completely unravel midway through.
                - "rating": "meets" | "partially_meets" | "vague" | "does_not_meet"
        - "domain_drift": true | false — whether the candidate shifted answers toward a different domain (e.g. general IT support, web development, project coordination, helpdesk) when asked role-specific questions
        - "domain_drift_explanation": a 1-sentence description of what domain the answers drifted toward and in which questions; null if domain_drift is false
    - "red_flags": array of objects — operational, credibility, or risk-weight flags only; must not duplicate jd_requirements_coverage gaps; empty array if none. Each object has:
        - "flag": concise statement of the issue
        - "literal_quote": copy the exact phrase from the transcript that triggered this flag. Write "NONE" if the flag is based on an absence rather than a specific statement.
        - "rationale": one sentence explaining why this warrants a flag and how it should affect the recruiter's decision.
    - "recommendation_basis": array of 2-3 short phrases naming the most decisive signals that drove the recommendation — reference the specific episode_dimension rating, red_flag, or jd_requirements_coverage entry with the highest decision weight (e.g. "outcome_orientation: vague across all stories", "ownership_language: credit-hogging pattern", "jd_requirements_coverage: stakeholder management not addressed")
    - "decision_rationale": a 1-2 sentence explanation of the recommendation, anchored to the signals named in recommendation_basis

    Return only valid JSON. No markdown fences, no extra text.
  PROMPT

  def initialize(analysis:, client: AnthropicClient.new)
    @analysis = analysis
    @client   = client
  end

  def call
    @analysis.transition_to!("analyzing")
    raise "No transcript available" if @analysis.transcript.blank?

    transcript  = @analysis.cleaned_transcript.presence || @analysis.transcript
    job_context = @analysis.job_role.to_prompt

    result = @client.complete(
      model:      MODEL,
      system:     [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      messages:   [{ role: "user", content: build_user_message(transcript, job_context) }],
      max_tokens: 6000
    )

    jd_fit_score = JdFitScoreCalculator.new(coverage: result.dig("structured_feedback", "jd_requirements_coverage")).score

    @analysis.update!(
      score: result["score"],
      summary: result["summary"],
      structured_feedback: result["structured_feedback"].merge(
        "recommendation"            => result["recommendation"],
        "jd_fit_score"              => jd_fit_score,
        "red_flags"                 => result["red_flags"],
        "recommendation_basis"      => result["recommendation_basis"],
        "decision_rationale"        => result["decision_rationale"]
      ),
      prompt_version: PROMPT_VERSION,
      status: "completed"
    )

    result
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
    OutcomeExamplesBuilder::Interview.new(
      role:              @analysis.job_role,
      exclude_candidate: candidate
    ).build(intro: [
      "Anonymised outcomes from past interviews for this role, reviewed by the hiring manager.",
      "Use these to calibrate how the hiring team distinguishes strong from weak interview performance."
    ])
  end
end
