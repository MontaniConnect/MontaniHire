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

  # All five dimensions at "meets" (1.0) → weighted sum = 1.0 × 10 = 10.0
  ALL_TOP_DIMS = {
    "episode_dimensions" => {
      "relevance_discipline"  => "meets",
      "ownership_language"    => "meets",
      "outcome_orientation"   => "meets",
      "adaptability_signal"   => "meets",
      "communication_clarity" => "meets"
    }
  }.freeze

  # All five dimensions at "partially_meets" (0.7) → weighted sum = 0.7 × 10 = 7.0
  ALL_MID_DIMS = {
    "episode_dimensions" => {
      "relevance_discipline"  => "partially_meets",
      "ownership_language"    => "partially_meets",
      "outcome_orientation"   => "partially_meets",
      "adaptability_signal"   => "partially_meets",
      "communication_clarity" => "partially_meets"
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
    # relevance_discipline meets (1.0, w=0.20) + outcome_orientation vague (0.4, w=0.30)
    # total_weight = 0.50, weighted = 0.20 + 0.12 = 0.32
    # score = (0.32 / 0.50) * 10 = 6.4
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "relevance_discipline" => "meets",
        "outcome_orientation"  => "vague"
      }
    })
    assert_equal 6.4, c.episode_score
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
    # Only ownership_language contributes: (1.0 * 0.10) / 0.10 * 10 = 10.0
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "ownership_language"  => "meets",
        "outcome_orientation" => "unknown_level"
      }
    })
    assert_equal 10.0, c.episode_score
  end

  # ── episode_tier ───────────────────────────────────────────────────────────

  test "episode_tier is Shortlist when score >= 7.5" do
    # all "meets" → 10.0 ≥ 7.5
    c = build_candidate(va_signals: ALL_TOP_DIMS)
    assert_equal "Shortlist", c.episode_tier
  end

  test "episode_tier is Borderline when score is between 5.0 and 7.4" do
    # all "partially_meets" → 7.0 (≥ 5.0 and < 7.5)
    c = build_candidate(va_signals: ALL_MID_DIMS)
    score = c.episode_score
    assert score >= 5.0 && score < 7.5, "Expected Borderline range, got #{score}"
    assert_equal "Borderline", c.episode_tier
  end

  test "episode_tier is Archive when score is below 5.0" do
    # all "does_not_meet" → 0.0 < 5.0
    c = build_candidate(va_signals: {
      "episode_dimensions" => {
        "relevance_discipline"  => "does_not_meet",
        "ownership_language"    => "does_not_meet",
        "outcome_orientation"   => "does_not_meet",
        "adaptability_signal"   => "does_not_meet",
        "communication_clarity" => "does_not_meet"
      }
    })
    assert_equal 0.0, c.episode_score
    assert_equal "Archive", c.episode_tier
  end

  test "episode_tier returns nil when episode_score is nil" do
    c = build_candidate(va_signals: {})
    assert_nil c.episode_tier
  end

  # ── jd_fit_tier ────────────────────────────────────────────────────────────

  test "jd_fit_tier is Shortlist when jd_fit_score >= 7.5" do
    c = build_candidate(va_signals: { "jd_fit_score" => 8.5 })
    assert_equal "Shortlist", c.jd_fit_tier
  end

  test "jd_fit_tier is Borderline when jd_fit_score is between 5.0 and 7.4" do
    c = build_candidate(va_signals: { "jd_fit_score" => 6.0 })
    assert_equal "Borderline", c.jd_fit_tier
  end

  test "jd_fit_tier is Archive when jd_fit_score is below 5.0" do
    c = build_candidate(va_signals: { "jd_fit_score" => 4.0 })
    assert_equal "Archive", c.jd_fit_tier
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

  # ── sync_shortlist_client_status (after_save callback) ────────────────────

  def build_shortlist_item(candidate, status: "pending")
    user      = candidate.user
    shortlist = Shortlist.create!(
      user:         user,
      title:        "SL #{SecureRandom.hex(3)}",
      client_email: "hm_#{SecureRandom.hex(3)}@test.com"
    )
    ShortlistItem.create!(shortlist: shortlist, candidate: candidate, client_status: status)
  end

  test "advancing to final_interview sets shortlist item to approved" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "final_interview")

    assert_equal "approved", item.reload.client_status
  end

  test "advancing to hired keeps shortlist item approved" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "hired")

    assert_equal "approved", item.reload.client_status
  end

  test "advancing to offer_declined keeps shortlist item approved" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "offer_declined")

    assert_equal "approved", item.reload.client_status
  end

  test "moving to not_selected sets shortlist item to rejected" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "not_selected")

    assert_equal "rejected", item.reload.client_status
  end

  test "moving to not_invited sets shortlist item to rejected" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "not_invited")

    assert_equal "rejected", item.reload.client_status
  end

  test "syncs all shortlist items when candidate has multiple" do
    c     = build_candidate
    item1 = build_shortlist_item(c, status: "pending")
    item2 = build_shortlist_item(c, status: "pending")

    c.update!(pipeline_stage: "final_interview")

    assert_equal "approved", item1.reload.client_status
    assert_equal "approved", item2.reload.client_status
  end

  test "stage with no mapping leaves shortlist items unchanged" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "approved")

    # cv_review and preliminary_interview have no entry in STAGE_CLIENT_STATUS
    c.update!(pipeline_stage: "cv_review")

    assert_equal "approved", item.reload.client_status
  end

  test "callback does not fire when an unrelated attribute changes" do
    c    = build_candidate
    item = build_shortlist_item(c, status: "pending")

    c.update!(name: "Updated Name")

    assert_equal "pending", item.reload.client_status
  end
end
