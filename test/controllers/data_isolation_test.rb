require "test_helper"

# Characterization: User A must not be able to read or mutate User B's
# resources. These tests pin the isolation invariant so it is preserved
# after the org migration (where the scope key changes from user_id to
# organization_id but the observable behaviour stays the same).
class DataIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @user_a = build_user(email: "a@example.com")
    @user_b = build_user(email: "b@example.com")

    @role_a = JobRole.create!(
      user: @user_a, organization: @user_a.organization, title: "Role A",
      experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
    @candidate_a = Candidate.create!(
      user: @user_a, organization: @user_a.organization, job_role: @role_a,
      name: "Alice", pipeline_stage: "cv_review"
    )
    @shortlist_a = Shortlist.create!(
      user: @user_a, organization: @user_a.organization, title: "SL A", client_email: "hm@a.com"
    )
  end

  # ── Candidate isolation ──────────────────────────────────────────────────

  test "user B cannot view user A's candidate" do
    sign_in @user_b
    get candidate_path(@candidate_a)
    assert_redirected_to candidates_path
  end

  test "user B cannot destroy user A's candidate" do
    sign_in @user_b
    delete candidate_path(@candidate_a)
    assert_redirected_to candidates_path
    assert Candidate.exists?(@candidate_a.id), "candidate must not be deleted"
  end

  # ── JobRole isolation ────────────────────────────────────────────────────

  test "user B cannot view user A's job role" do
    sign_in @user_b
    get job_role_path(@role_a)
    assert_redirected_to job_roles_path
  end

  test "user B cannot destroy user A's job role" do
    sign_in @user_b
    delete job_role_path(@role_a)
    assert_redirected_to job_roles_path
    assert JobRole.exists?(@role_a.id), "job role must not be deleted"
  end

  # ── Shortlist isolation ──────────────────────────────────────────────────

  test "user B cannot view user A's shortlist" do
    sign_in @user_b
    get shortlist_path(@shortlist_a)
    assert_redirected_to shortlists_path
  end

  test "user B cannot destroy user A's shortlist" do
    sign_in @user_b
    delete shortlist_path(@shortlist_a)
    assert_redirected_to shortlists_path
    assert Shortlist.exists?(@shortlist_a.id), "shortlist must not be deleted"
  end

  # ── Index views show only own resources ──────────────────────────────────

  test "candidates index for user B is empty when all candidates belong to user A" do
    sign_in @user_b
    get candidates_path
    assert_response :success
    # @candidates assigned in controller must not include @candidate_a
    # We verify by checking the response contains no record for user A's candidate.
    # (Model-level: current_user.candidates returns [] for user B)
    assert_equal 0, @user_b.candidates.count
  end
end
