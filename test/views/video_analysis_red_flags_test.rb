require "test_helper"

# Tests that video_analyses/show.html.erb renders red_flags correctly for
# both the legacy flat-string shape and the new CoT object shape
# {flag:, literal_quote:, rationale:} added in episode prompt v9.
class VideoAnalysisRedFlagsTest < ActionDispatch::IntegrationTest
  setup do
    @user    = build_user(email: "rftest@example.com")
    @org     = @user.organization
    @role    = JobRole.create!(
      organization: @org, user: @user,
      title: "Test Role", experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
  end

  def make_va(red_flags_value)
    VideoAnalysis.create!(
      organization: @org, user: @user, job_role: @role,
      candidate_name: "Test Candidate",
      transcript: "interview transcript",
      status: "completed",
      structured_feedback: { "red_flags" => red_flags_value }
    )
  end

  # ── Object shape (new CoT format) ────────────────────────────────────────────

  test "renders flag text from object-shaped red flag" do
    va = make_va([{ "flag" => "Frequent job hopping", "literal_quote" => "Q1 2021 – Q2 2021 at Acme", "rationale" => "Four roles in under three years." }])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Frequent job hopping", response.body
  end

  test "renders rationale from object-shaped red flag" do
    va = make_va([{ "flag" => "Ownership gap", "literal_quote" => "assisted the team", "rationale" => "Bullet points are consistently passive." }])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Bullet points are consistently passive.", response.body
  end

  test "renders literal_quote in blockquote for object-shaped red flag" do
    va = make_va([{ "flag" => "Scope exaggeration", "literal_quote" => "led company-wide transformation", "rationale" => "No headcount or budget evidence." }])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "led company-wide transformation", response.body
    assert_select "blockquote", minimum: 1
  end

  test "renders multiple object-shaped red flags" do
    flags = [
      { "flag" => "Flag A", "literal_quote" => "quote A", "rationale" => "rationale A" },
      { "flag" => "Flag B", "literal_quote" => "quote B", "rationale" => "rationale B" }
    ]
    va = make_va(flags)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Flag A", response.body
    assert_match "Flag B", response.body
    assert_match "rationale A", response.body
    assert_match "rationale B", response.body
  end

  test "skips blockquote when object-shaped flag has no literal_quote" do
    va = make_va([{ "flag" => "No evidence", "literal_quote" => "", "rationale" => "Nothing found." }])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "No evidence", response.body
    assert_select "blockquote", count: 0
  end

  # ── Legacy flat-string shape ───────────────────────────────────────────────────

  test "renders legacy flat-string red flags as plain list items" do
    va = make_va(["Unexplained employment gap", "No measurable outcomes"])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Unexplained employment gap", response.body
    assert_match "No measurable outcomes", response.body
    assert_select "blockquote", count: 0
  end

  # ── Mixed legacy + new (forward compat) ───────────────────────────────────────

  test "renders mixed array of string and object red flags without error" do
    flags = [
      "Legacy string flag",
      { "flag" => "New object flag", "literal_quote" => "verbatim text", "rationale" => "Explanation." }
    ]
    va = make_va(flags)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_match "Legacy string flag", response.body
    assert_match "New object flag", response.body
    assert_match "Explanation.", response.body
    assert_select "blockquote", count: 1
  end

  # ── No flags ──────────────────────────────────────────────────────────────────

  test "renders without errors when red_flags is absent" do
    va = make_va(nil)
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
    assert_select "blockquote", count: 0
  end

  test "renders without errors when red_flags is empty array" do
    va = make_va([])
    sign_in @user
    get video_analysis_path(va)
    assert_response :success
  end
end
