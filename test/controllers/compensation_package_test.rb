require "test_helper"

class CompensationPackageTest < ActionDispatch::IntegrationTest
  def setup
    @user      = build_user
    @org       = @user.organization
    @job_role  = JobRole.create!(
      organization: @org, user: @user,
      title: "Test Role", experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
    cv = CvAnalysis.new(
      organization: @org, user: @user, job_role: @job_role,
      candidate_name: "Test Candidate", status: "completed"
    )
    cv.cv.attach(io: StringIO.new("pdf"), filename: "cv.pdf", content_type: "application/pdf")
    cv.save!
    @candidate = Candidate.create!(
      organization: @org, user: @user, job_role: @job_role,
      cv_analysis: cv, name: "Test Candidate", pipeline_stage: "cv_review"
    )
    sign_in @user
  end

  # ── valid input saves correctly ──────────────────────────────────────────

  test "valid compensation_package is saved" do
    patch update_compensation_package_candidate_path(@candidate),
          params: { compensation_package: "USD 5,200.00/mo" }
    assert_redirected_to candidate_path(@candidate)
    assert_equal "USD 5,200.00/mo", @candidate.reload.compensation_package
  end

  test "leading and trailing whitespace is stripped before saving" do
    patch update_compensation_package_candidate_path(@candidate),
          params: { compensation_package: "  USD 5,200.00/mo  " }
    assert_equal "USD 5,200.00/mo", @candidate.reload.compensation_package
  end

  # ── blank input saves nil, not empty string ───────────────────────────────

  test "blank input saves nil" do
    @candidate.update!(compensation_package: "USD 5,200.00/mo")
    patch update_compensation_package_candidate_path(@candidate),
          params: { compensation_package: "" }
    assert_redirected_to candidate_path(@candidate)
    assert_nil @candidate.reload.compensation_package
  end

  test "whitespace-only input saves nil" do
    patch update_compensation_package_candidate_path(@candidate),
          params: { compensation_package: "   " }
    assert_nil @candidate.reload.compensation_package
  end
end
