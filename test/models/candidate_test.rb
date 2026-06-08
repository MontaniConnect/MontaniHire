require "test_helper"

class CandidateTest < ActiveSupport::TestCase
  def build_candidate(cv_signals: {}, va_signals: {}, cv_score: nil, va_score: nil)
    user     = User.create!(email: "test_#{SecureRandom.hex(4)}@example.com", name: "Test")
    job_role = JobRole.create!(
      user: user,
      title: "Test Role",
      experience_level: "mid",
      required_skills: "CRM experience",
      responsibilities: "Manage pipeline"
    )

    cv = CvAnalysis.new(
      user: user,
      job_role: job_role,
      candidate_name: "Test Candidate",
      status: "completed",
      score: cv_score,
      structured_feedback: cv_signals
    )
    cv.cv.attach(io: StringIO.new("test"), filename: "cv.pdf", content_type: "application/pdf")
    cv.save!

    va = VideoAnalysis.new(
      user: user,
      job_role: job_role,
      candidate_name: "Test Candidate",
      status: "completed",
      score: va_score,
      structured_feedback: va_signals
    )
    va.video.attach(io: StringIO.new("test"), filename: "video.mp4", content_type: "video/mp4")
    va.save!

    Candidate.create!(
      user: user,
      job_role: job_role,
      name: "Test Candidate",
      pipeline_stage: "preliminary_interview",
      cv_analysis: cv,
      video_analysis: va
    )
  end

  ALL_TOP_DIMS = {
    "episode_dimensions" => {
      "elaboration_quality"  => "rich",
      "ownership_language"   => "clear_ownership",
      "outcome_orientation"  => "outcome_led",
      "directness"           => "direct",
      "stakeholder_fluency"  => "strong",
      "relevance_discipline" => "disciplined",
      "adaptability_signal"  => "adaptive"
    }
  }.freeze

  ALL_MID_DIMS = {
    "episode_dimensions" => {
      "elaboration_quality"  => "adequate",
      "ownership_language"   => "shared_credit",
      "outcome_orientation"  => "outcome_aware",
      "directness"           => "mostly_direct",
      "stakeholder_fluency"  => "adequate",
      "relevance_discipline" => "mostly_relevant",
      "adaptability_signal"  => "flexible"
    }
  }.freeze

  # ── episode_score ──────────────────────────────────────────────────────────

  test "episode_score returns 10.0 when all dimensions are top level" do
    c = build_candidate(va_signals: ALL_TOP_DIMS)
    assert_equal 10.0, c.episode_score
  end

  test "episode_score returns 7.0 when all dimensions are mid level" do
    c = build_candidate(va_signals: ALL_MID_DIMS)
    assert_equal 7.0, c.episode_score
  end

  test "episode_score computes weighted average across mixed dimensions" do
    # elaboration_quality rich (1.0, w=0.25) + outcome_orientation activity_focused (0.4, w=0.20)
    # total_weight = 0.45, weighted = 0.25 + 0.08 = 0.33
    # score = (0.33 / 0.45) * 10 = 7.3 (rounded to 1dp)
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "elaboration_quality"  => "rich",
        "outcome_orientation"  => "activity_focused"
      }
    })
    assert_equal 7.3, c.episode_score
  end

  test "episode_score returns nil when no episode_dimensions present" do
    c = build_candidate(va_signals: { "jd_fit_score" => 6.5 })
    assert_nil c.episode_score
  end

  test "episode_score returns nil when video_analysis is absent" do
    user     = User.create!(email: "test_#{SecureRandom.hex(4)}@example.com", name: "Test")
    job_role = JobRole.create!(
      user: user,
      title: "Test Role",
      experience_level: "mid",
      required_skills: "CRM experience",
      responsibilities: "Manage pipeline"
    )
    c = Candidate.create!(user: user, job_role: job_role, name: "No Video", pipeline_stage: "cv_review")
    assert_nil c.episode_score
  end

  test "episode_score skips unknown level values" do
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "elaboration_quality" => "unknown_level",
        "ownership_language"  => "clear_ownership"
      }
    })
    # only ownership_language contributes: (1.0 * 0.20) / 0.20 * 10 = 10.0
    assert_equal 10.0, c.episode_score
  end

  # ── episode_tier ───────────────────────────────────────────────────────────

  test "episode_tier is Shortlist when score >= 7.0" do
    c = build_candidate(va_signals: ALL_TOP_DIMS)
    assert_equal "Shortlist", c.episode_tier
  end

  test "episode_tier is Hold when score is between 5.0 and 6.9" do
    # Build dimensions to produce a ~6.0 score
    # elaboration_quality surface_level (0.4, w=0.25) + ownership_language clear_ownership (1.0, w=0.20)
    # = (0.10 + 0.20) / 0.45 * 10 = 6.7
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "elaboration_quality" => "surface_level",
        "ownership_language"  => "clear_ownership"
      }
    })
    score = c.episode_score
    assert score >= 5.0 && score < 7.0, "Expected Hold range, got #{score}"
    assert_equal "Hold", c.episode_tier
  end

  test "episode_tier is Pass when score is below 5.0" do
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "elaboration_quality"  => "absent",
        "ownership_language"   => "absent",
        "outcome_orientation"  => "absent",
        "directness"           => "absent",
        "stakeholder_fluency"  => "absent",
        "relevance_discipline" => "absent",
        "adaptability_signal"  => "absent"
      }
    })
    assert_equal 0.0, c.episode_score
    assert_equal "Pass", c.episode_tier
  end

  test "episode_tier returns nil when episode_score is nil" do
    c = build_candidate(va_signals: {})
    assert_nil c.episode_tier
  end

  # ── jd_fit_tier ────────────────────────────────────────────────────────────

  test "jd_fit_tier is Shortlist when jd_fit_score >= 7.0" do
    c = build_candidate(va_signals: { "jd_fit_score" => 8.5 })
    assert_equal "Shortlist", c.jd_fit_tier
  end

  test "jd_fit_tier is Hold when jd_fit_score is between 5.0 and 6.9" do
    c = build_candidate(va_signals: { "jd_fit_score" => 6.0 })
    assert_equal "Hold", c.jd_fit_tier
  end

  test "jd_fit_tier is Pass when jd_fit_score is below 5.0" do
    c = build_candidate(va_signals: { "jd_fit_score" => 4.0 })
    assert_equal "Pass", c.jd_fit_tier
  end

  test "jd_fit_tier returns nil when jd_fit_score is absent" do
    c = build_candidate(va_signals: {})
    assert_nil c.jd_fit_tier
  end

  # ── domain_drift? ──────────────────────────────────────────────────────────

  test "domain_drift? returns true when domain_drift is true" do
    c = build_candidate(va_signals: { "domain_drift" => true })
    assert c.domain_drift?
  end

  test "domain_drift? returns false when domain_drift is false" do
    c = build_candidate(va_signals: { "domain_drift" => false })
    assert_not c.domain_drift?
  end

  test "domain_drift? returns false when domain_drift is absent" do
    c = build_candidate(va_signals: {})
    assert_not c.domain_drift?
  end

  # ── cv_interview_gap? ──────────────────────────────────────────────────────

  test "cv_interview_gap? returns true when CV fit exceeds JD fit by >= 2.0" do
    c = build_candidate(
      cv_signals: { "cv_fit_score" => 8.0 },
      va_signals:  { "jd_fit_score" => 5.5 }
    )
    assert c.cv_interview_gap?
  end

  test "cv_interview_gap? returns false when gap is less than 2.0" do
    c = build_candidate(
      cv_signals: { "cv_fit_score" => 7.0 },
      va_signals:  { "jd_fit_score" => 5.5 }
    )
    assert_not c.cv_interview_gap?
  end

  test "cv_interview_gap? returns false when scores are equal" do
    c = build_candidate(
      cv_signals: { "cv_fit_score" => 6.0 },
      va_signals:  { "jd_fit_score" => 6.0 }
    )
    assert_not c.cv_interview_gap?
  end

  test "cv_interview_gap? returns false when either score is missing" do
    c1 = build_candidate(cv_signals: { "cv_fit_score" => 8.0 }, va_signals: {})
    c2 = build_candidate(cv_signals: {}, va_signals: { "jd_fit_score" => 4.0 })
    assert_not c1.cv_interview_gap?
    assert_not c2.cv_interview_gap?
  end
end
