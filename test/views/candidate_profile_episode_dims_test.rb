require "test_helper"

# Tests that video_analyses/show.html.erb renders episode_dimensions correctly
# for both legacy flat-string values and new CoT object shape
# {rating:, literal_quote:, tier_check:} added in episode prompt v9.
#
# Note: candidates/_candidate_profile.html.erb also has episode_dimensions
# rendering but is not yet routed to any HTTP path; the authoritative view
# for recruiter-facing episode scoring is video_analyses/show.html.erb.
class CandidateProfileEpisodeDimsTest < ActionDispatch::IntegrationTest
  # Level → display label (from dim_meta shared_levels in show.html.erb)
  LEVEL_LABELS = {
    "meets"         => "Meets",
    "partially_meets" => "Partially Meets",
    "vague"         => "Vague",
    "does_not_meet" => "Does Not Meet"
  }.freeze

  setup do
    @user = build_user(email: "epdims@example.com")
    @org  = @user.organization
    @role = JobRole.create!(
      organization: @org, user: @user,
      title: "Test Role", experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
  end

  def make_va(episode_dimensions)
    VideoAnalysis.create!(
      organization: @org, user: @user, job_role: @role,
      candidate_name: "Test Candidate",
      transcript: "interview transcript",
      status: "completed",
      structured_feedback: { "episode_dimensions" => episode_dimensions }
    )
  end

  # ── CoT object shape (new format) ─────────────────────────────────────────────

  test "renders Meets label for outcome_orientation meets in object shape" do
    dims = { "outcome_orientation" => { "rating" => "meets", "literal_quote" => "grew ARR by 40%", "tier_check" => "meets threshold" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Meets", response.body
  end

  test "renders Partially Meets label for outcome_orientation partially_meets in object shape" do
    dims = { "outcome_orientation" => { "rating" => "partially_meets", "literal_quote" => "improved metrics", "tier_check" => "partially meets" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Partially Meets", response.body
  end

  test "renders Vague label for adaptability_signal vague in object shape" do
    dims = { "adaptability_signal" => { "rating" => "vague", "literal_quote" => "adapted to challenges", "tier_check" => "vague" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Vague", response.body
  end

  test "renders Does Not Meet label for relevance_discipline does_not_meet in object shape" do
    dims = { "relevance_discipline" => { "rating" => "does_not_meet", "literal_quote" => "NONE", "tier_check" => "no domain evidence" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Does Not Meet", response.body
  end

  test "renders multiple CoT object dimensions without error" do
    dims = {
      "outcome_orientation"   => { "rating" => "meets",           "literal_quote" => "grew ARR 40%",  "tier_check" => "meets" },
      "adaptability_signal"   => { "rating" => "partially_meets", "literal_quote" => "pivoted approach","tier_check" => "partially meets" },
      "communication_clarity" => { "rating" => "vague",           "literal_quote" => "communicated",  "tier_check" => "vague" }
    }
    va = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Meets",          response.body
    assert_match "Partially Meets", response.body
    assert_match "Vague",          response.body
  end

  test "renders contribution formula for CoT object dimensions" do
    # outcome_orientation meets (1.0) × 30% = 0.3
    dims = { "outcome_orientation" => { "rating" => "meets", "literal_quote" => "grew ARR 40%", "tier_check" => "meets" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "30%", response.body
  end

  # ── Legacy flat-string shape ──────────────────────────────────────────────────

  test "renders Meets label for outcome_orientation meets in legacy string shape" do
    dims = { "outcome_orientation" => "meets" }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Meets", response.body
  end

  test "renders Partially Meets label for adaptability_signal partially_meets in legacy string shape" do
    dims = { "adaptability_signal" => "partially_meets" }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Partially Meets", response.body
  end

  test "renders Does Not Meet label for relevance_discipline does_not_meet in legacy string shape" do
    dims = { "relevance_discipline" => "does_not_meet" }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Does Not Meet", response.body
  end

  # ── Unknown / invalid values ──────────────────────────────────────────────────

  test "renders without error when object shape has unknown rating value" do
    dims = { "outcome_orientation" => { "rating" => "unknown_level", "literal_quote" => "something", "tier_check" => "?" } }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
  end

  test "renders without error when dimension value is nil" do
    dims = { "outcome_orientation" => nil }
    va   = make_va(dims)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
  end

  # ── No episode_dimensions ─────────────────────────────────────────────────────

  test "renders without error when episode_dimensions is absent" do
    va = make_va(nil)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
  end
end
