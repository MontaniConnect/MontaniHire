require "test_helper"

# Regression tests for HIGH-2 and HIGH-3: unscoped Candidate.find_by calls
# that could surface a candidate from a different organisation when cv_analysis_id
# or video_analysis_id values happen to match across org boundaries.
#
# Each test constructs the exact data-mismatch scenario described in the audit:
# an org-B candidate whose analysis FK points to an org-A analysis record.
# The scoped query must return nil; the old unscoped query would have returned
# the cross-org candidate.
class OrgIsolationCandidateLookupTest < ActionDispatch::IntegrationTest
  # ── Shared helpers ──────────────────────────────────────────────────────────

  def make_job_role(org, user)
    JobRole.create!(
      organization: org, user: user,
      title: "Role", experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
  end

  def make_cv_analysis(org, user, job_role, status: "pending")
    CvAnalysis.create!(
      organization: org, user: user, job_role: job_role,
      drive_file_id: "fake-#{SecureRandom.hex(4)}",
      candidate_name: "CV Candidate",
      status: status
    )
  end

  def make_video_analysis(org, user, job_role)
    VideoAnalysis.create!(
      organization: org, user: user, job_role: job_role,
      candidate_name: "VA Candidate",
      transcript: "interview transcript here",
      status: "pending"
    )
  end

  def make_candidate(org, user, job_role, **attrs)
    Candidate.create!(
      organization: org, user: user, job_role: job_role,
      name: "Test Candidate", pipeline_stage: "preliminary_interview",
      **attrs
    )
  end

  # ── HIGH-2: ShortlistItemsController#create ─────────────────────────────────
  #
  # Path: create action, else-branch (shareable_type / shareable_id params).
  # The bug: after building the ShortlistItem from the org-A analysis,
  # the old code called Candidate.find_by(cv_analysis_id: ...) globally,
  # which would return org-B's candidate whose cv_analysis_id was set to
  # org-A's analysis id.

  test "shortlist_items create: cross-org candidate is not linked via cv_analysis_id mismatch" do
    # Org A — the signed-in user
    user_a = build_user(email: "sic_a@example.com")
    org_a  = user_a.organization
    role_a = make_job_role(org_a, user_a)
    cv_a   = make_cv_analysis(org_a, user_a, role_a)
    sl_a   = Shortlist.create!(organization: org_a, user: user_a,
                                title: "SL A", client_email: "hm@a.com")

    # Org B — a candidate whose cv_analysis_id has been corrupted to point
    # at org A's analysis (the mismatch scenario from the audit).
    user_b = build_user(email: "sic_b@example.com")
    org_b  = user_b.organization
    role_b = make_job_role(org_b, user_b)
    cand_b = make_candidate(org_b, user_b, role_b)
    cand_b.update_columns(cv_analysis_id: cv_a.id)

    sign_in user_a
    post shortlist_shortlist_items_path(sl_a),
         params: { shareable_type: "CvAnalysis", shareable_id: cv_a.id }

    item = ShortlistItem.order(:id).last
    assert_equal cv_a.id, item.cv_analysis_id, "item must reference org A's analysis"
    assert_nil item.candidate_id,
               "org B's candidate (id=#{cand_b.id}) must NOT be attached to the item"
  end

  # ── HIGH-3: VideoAnalysesController#reanalyse ──────────────────────────────
  #
  # Path: reanalyse action, after the transcript-blank guard.
  # The bug: the old Candidate.find_by(video_analysis_id: ...) was unscoped,
  # so it would find org-B's candidate whose video_analysis_id pointed at
  # org-A's analysis. Because that candidate has a completed CV, the old code
  # would have proceeded past the cv-ready guard to call ClaudeAnalysisService.
  # The new scoped query returns nil → redirects with the CV-not-ready alert.

  test "video_analyses reanalyse: cross-org candidate is not found via video_analysis_id mismatch" do
    # Org A — signed-in user's analysis; no candidate in org A links to it
    user_a = build_user(email: "var_a@example.com")
    org_a  = user_a.organization
    role_a = make_job_role(org_a, user_a)
    va_a   = make_video_analysis(org_a, user_a, role_a)

    # Org B — candidate with a completed CV whose video_analysis_id is corrupted
    # to point at org A's analysis. With the old unscoped query this candidate
    # would be found and its completed CV would pass the cv-ready guard,
    # causing ClaudeAnalysisService to be invoked for org-A's analysis using
    # org-B's candidate data.
    user_b = build_user(email: "var_b@example.com")
    org_b  = user_b.organization
    role_b = make_job_role(org_b, user_b)
    cv_b   = make_cv_analysis(org_b, user_b, role_b, status: "completed")
    cand_b = make_candidate(org_b, user_b, role_b, cv_analysis: cv_b)
    cand_b.update_columns(video_analysis_id: va_a.id)

    sign_in user_a
    post reanalyse_video_analysis_path(va_a)

    assert_redirected_to video_analysis_path(va_a)
    assert_match "CV analysis must be completed", flash[:alert],
                 "action must treat candidate as nil — org B's candidate must not be visible"
    va_a.reload
    assert_not_equal "analyzing", va_a.status,
                     "ClaudeAnalysisService must not have been invoked (no cross-org candidate found)"
  end
end
