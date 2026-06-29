require "test_helper"

class CandidatesExportMdTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = build_user(email: "owner@example.com")
    @member = User.create!(
      email: "member@example.com", name: "Member User",
      role: "member", organization: @owner.organization
    )
    @role = JobRole.create!(
      user: @owner, organization: @owner.organization,
      title: "BDR", experience_level: "mid",
      required_skills: "sales", responsibilities: "outreach"
    )
    @hired = Candidate.create!(
      user: @owner, organization: @owner.organization,
      job_role: @role, name: "Jane Hired",
      email: "jane@example.com",
      pipeline_stage: "hired"
    )
    @cv_review = Candidate.create!(
      user: @owner, organization: @owner.organization,
      job_role: @role, name: "Bob Pending",
      pipeline_stage: "cv_review"
    )
  end

  test "owner can download markdown for hired candidate" do
    sign_in @owner
    get export_md_candidate_path(@hired)
    assert_response :success
    assert_equal "text/markdown", response.content_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "jane-hired"
  end

  test "downloaded content contains candidate name and email" do
    sign_in @owner
    get export_md_candidate_path(@hired)
    assert_includes response.body, "Jane Hired"
    assert_includes response.body, "jane@example.com"
  end

  test "non-owner member is redirected" do
    sign_in @member
    get export_md_candidate_path(@hired)
    assert_redirected_to root_path
  end

  test "owner cannot export non-hired candidate" do
    sign_in @owner
    get export_md_candidate_path(@cv_review)
    assert_redirected_to candidate_path(@cv_review)
  end

  test "exports without error when cv_analysis is absent" do
    sign_in @owner
    assert_nil @hired.cv_analysis
    get export_md_candidate_path(@hired)
    assert_response :success
    assert_includes response.body, "CV analysis not completed"
  end

  test "exports without error when video_analysis is absent" do
    sign_in @owner
    assert_nil @hired.video_analysis
    get export_md_candidate_path(@hired)
    assert_response :success
    assert_includes response.body, "Video interview analysis not completed"
  end
end
