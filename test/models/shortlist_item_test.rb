require "test_helper"

class ShortlistItemTest < ActiveSupport::TestCase
  # ── Helpers ───────────────────────────────────────────────────────────────

  def build_user
    UserRegistrationService.new(email: "u_#{SecureRandom.hex(4)}@test.com", name: "Test User").call.user
  end

  def build_shortlist(user)
    Shortlist.create!(
      user:         user,
      organization: user.organization,
      title:        "Test Shortlist",
      client_email: "client@test.com"
    )
  end

  def build_candidate(user, stage: "client_interview")
    Candidate.create!(
      user:           user,
      organization:   user.organization,
      name:           "Jane Doe #{SecureRandom.hex(3)}",
      pipeline_stage: stage
    )
  end

  def build_item(shortlist, candidate, status: "pending")
    ShortlistItem.create!(
      shortlist:     shortlist,
      candidate:     candidate,
      client_status: status
    )
  end

  def build_candidate_with_analyses(user, va_signals: {}, cv_signals: {})
    org      = user.organization
    job_role = JobRole.create!(
      user: user, organization: org,
      title: "Role #{SecureRandom.hex(3)}", experience_level: "mid",
      required_skills: "x", responsibilities: "y"
    )
    cv = CvAnalysis.new(
      user: user, organization: org, job_role: job_role,
      candidate_name: "Test", status: "completed",
      structured_feedback: cv_signals
    )
    cv.cv.attach(io: StringIO.new("test"), filename: "cv.pdf", content_type: "application/pdf")
    cv.save!
    va = VideoAnalysis.new(
      user: user, organization: org, job_role: job_role,
      candidate_name: "Test", status: "completed",
      structured_feedback: va_signals
    )
    va.video.attach(io: StringIO.new("test"), filename: "video.mp4", content_type: "video/mp4")
    va.save!
    Candidate.create!(
      user: user, organization: org, job_role: job_role,
      name: "Test #{SecureRandom.hex(3)}", pipeline_stage: "client_interview",
      cv_analysis: cv, video_analysis: va
    )
  end

  ALL_TOP_DIMS = {
    "episode_dimensions" => {
      "relevance_discipline"  => "meets",
      "ownership_language"    => "meets",
      "outcome_orientation"   => "meets",
      "adaptability_signal"   => "meets",
      "communication_clarity" => "meets"
    }
  }.freeze

  # ── score (fallback chain) ─────────────────────────────────────────────────

  test "score returns episode_score when video_analysis has episode_dimensions" do
    user      = build_user
    candidate = build_candidate_with_analyses(user, va_signals: ALL_TOP_DIMS)
    item      = build_item(build_shortlist(user), candidate)
    assert_equal 10.0, item.score
  end

  test "score falls back to cv_fit_score when episode_score is nil" do
    user      = build_user
    candidate = build_candidate_with_analyses(
      user,
      va_signals: {},
      cv_signals: { "cv_fit_score" => 6.5 }
    )
    item = build_item(build_shortlist(user), candidate)
    assert_nil candidate.episode_score
    assert_equal 6.5, item.score
  end

  test "score falls back to cv_fit_score when video_analysis is absent" do
    user     = build_user
    org      = user.organization
    job_role = JobRole.create!(
      user: user, organization: org,
      title: "Role #{SecureRandom.hex(3)}", experience_level: "mid",
      required_skills: "x", responsibilities: "y"
    )
    cv = CvAnalysis.new(
      user: user, organization: org, job_role: job_role,
      candidate_name: "Test", status: "completed",
      structured_feedback: { "cv_fit_score" => 7.8 }
    )
    cv.cv.attach(io: StringIO.new("test"), filename: "cv.pdf", content_type: "application/pdf")
    cv.save!
    candidate = Candidate.create!(
      user: user, organization: org, job_role: job_role,
      name: "No Video #{SecureRandom.hex(3)}", pipeline_stage: "cv_review",
      cv_analysis: cv
    )
    item = build_item(build_shortlist(user), candidate)
    assert_equal 7.8, item.score
  end

  test "score returns nil when both episode_score and cv_fit_score are absent" do
    user      = build_user
    candidate = build_candidate_with_analyses(user, va_signals: {}, cv_signals: {})
    item      = build_item(build_shortlist(user), candidate)
    assert_nil item.score
  end

  # ── sync_candidate_stage! ─────────────────────────────────────────────────

  test "approved status advances candidate to final_interview" do
    user      = build_user
    candidate = build_candidate(user, stage: "client_interview")
    item      = build_item(build_shortlist(user), candidate, status: "pending")

    item.sync_candidate_stage!("approved")

    assert_equal "final_interview", candidate.reload.pipeline_stage
  end

  test "rejected status moves candidate to not_selected" do
    user      = build_user
    candidate = build_candidate(user, stage: "client_interview")
    item      = build_item(build_shortlist(user), candidate, status: "approved")

    item.sync_candidate_stage!("rejected")

    assert_equal "not_selected", candidate.reload.pipeline_stage
  end

  test "pending status returns candidate to client_interview" do
    user      = build_user
    candidate = build_candidate(user, stage: "final_interview")
    item      = build_item(build_shortlist(user), candidate, status: "approved")

    item.sync_candidate_stage!("pending")

    assert_equal "client_interview", candidate.reload.pipeline_stage
  end

  test "sync_candidate_stage! does not trigger after_save callback on candidate" do
    user      = build_user
    shortlist = build_shortlist(user)
    candidate = build_candidate(user, stage: "client_interview")
    item      = build_item(shortlist, candidate, status: "pending")

    # A second shortlist item on the same candidate — if the after_save callback
    # fired, it would overwrite this item's client_status back to "pending"
    item2 = build_item(
      Shortlist.create!(user: user, organization: user.organization, title: "Other", client_email: "other@test.com"),
      candidate,
      status: "approved"
    )

    item.sync_candidate_stage!("approved")

    # Candidate stage moved forward
    assert_equal "final_interview", candidate.reload.pipeline_stage
    # item2 is untouched — callback did NOT fire
    assert_equal "approved", item2.reload.client_status
  end

  test "sync_candidate_stage! is a no-op when candidate is nil" do
    user      = build_user
    shortlist = build_shortlist(user)
    item      = ShortlistItem.create!(shortlist: shortlist, client_status: "pending")

    assert_nothing_raised { item.sync_candidate_stage!("approved") }
  end

  # ── toggle_final_interview_no_show! ───────────────────────────────────────

  test "toggle sets no_show to true when currently false" do
    user      = build_user
    candidate = build_candidate(user)
    item      = build_item(build_shortlist(user), candidate)

    assert_equal false, candidate.final_interview_no_show

    item.toggle_final_interview_no_show!

    assert_equal true, candidate.reload.final_interview_no_show
  end

  test "toggle clears no_show when currently true" do
    user      = build_user
    candidate = build_candidate(user)
    candidate.update_columns(final_interview_no_show: true)
    item      = build_item(build_shortlist(user), candidate)

    item.toggle_final_interview_no_show!

    assert_equal false, candidate.reload.final_interview_no_show
  end

  test "toggle is a no-op when candidate is nil" do
    user = build_user
    item = ShortlistItem.create!(shortlist: build_shortlist(user), client_status: "pending")

    assert_nothing_raised { item.toggle_final_interview_no_show! }
  end

  # ── final_interview_no_show? ──────────────────────────────────────────────

  test "final_interview_no_show? returns true when flag is set" do
    user      = build_user
    candidate = build_candidate(user)
    candidate.update_columns(final_interview_no_show: true)
    item      = build_item(build_shortlist(user), candidate)

    assert item.final_interview_no_show?
  end

  test "final_interview_no_show? returns false when flag is clear" do
    user      = build_user
    candidate = build_candidate(user)
    item      = build_item(build_shortlist(user), candidate)

    assert_not item.final_interview_no_show?
  end

  test "final_interview_no_show? returns false when candidate is nil" do
    user = build_user
    item = ShortlistItem.create!(shortlist: build_shortlist(user), client_status: "pending")

    assert_not item.final_interview_no_show?
  end
end
