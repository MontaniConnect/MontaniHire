require "test_helper"

class SharedShortlistsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = UserRegistrationService.new(email: "recruiter_#{SecureRandom.hex(4)}@test.com", name: "Recruiter").call.user
    @shortlist = Shortlist.create!(
      user:         @user,
      organization: @user.organization,
      title:        "Test Shortlist",
      client_email: "hm@test.com"
    )
    @candidate = Candidate.create!(
      user:           @user,
      organization:   @user.organization,
      name:           "Test Candidate",
      pipeline_stage: "final_interview"
    )
    @item = ShortlistItem.create!(
      shortlist:     @shortlist,
      candidate:     @candidate,
      client_status: "approved"
    )
  end

  def verify_session!
    post verify_shared_shortlist_path(@shortlist.token), params: { email: "hm@test.com" }
  end

  # ── no_show ───────────────────────────────────────────────────────────────

  test "no_show sets final_interview_no_show to true when clear" do
    verify_session!
    assert_equal false, @candidate.final_interview_no_show

    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_equal true, @candidate.reload.final_interview_no_show
  end

  test "no_show clears final_interview_no_show when already set" do
    @candidate.update_columns(final_interview_no_show: true)
    verify_session!

    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_equal false, @candidate.reload.final_interview_no_show
  end

  test "no_show redirects back to the item page" do
    verify_session!

    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_redirected_to shared_shortlist_item_path(@shortlist.token, @item)
  end

  test "no_show sets a notice when marking as no show" do
    verify_session!

    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_equal "Marked as no show.", flash[:notice]
  end

  test "no_show sets a notice when clearing no show" do
    @candidate.update_columns(final_interview_no_show: true)
    verify_session!

    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_equal "No show cleared.", flash[:notice]
  end

  test "no_show requires verification" do
    patch shared_shortlist_no_show_path(@shortlist.token, @item)

    assert_redirected_to shared_shortlist_path(@shortlist.token)
  end

  test "no_show returns 404 for an invalid token" do
    patch shared_shortlist_no_show_path("invalid_token_xyz", @item)

    assert_response :not_found
  end

  # ── show — Gmail button ───────────────────────────────────────────────────

  test "show renders Gmail button when a candidate is in final_interview" do
    @candidate.update_columns(pipeline_stage: "final_interview")
    verify_session!

    get shared_shortlist_path(@shortlist.token)

    assert_response :success
    assert_match "mail.google.com", response.body
  end

  test "show does not render Gmail button when no candidates are selected" do
    @candidate.update_columns(pipeline_stage: "client_interview")
    verify_session!

    get shared_shortlist_path(@shortlist.token)

    assert_response :success
    refute_match "mail.google.com", response.body
  end

  # ── decision summary stage bucketing ─────────────────────────────────────

  test "show renders selected candidate name when stage is final_interview" do
    @candidate.update_columns(pipeline_stage: "final_interview")
    verify_session!

    get shared_shortlist_path(@shortlist.token)

    assert_response :success
    assert_match @candidate.name, response.body
  end

  test "show renders declined candidate name when stage is not_selected" do
    not_selected_candidate = Candidate.create!(
      user: @user, organization: @user.organization,
      name: "Declined Person", pipeline_stage: "not_selected"
    )
    ShortlistItem.create!(shortlist: @shortlist, candidate: not_selected_candidate, client_status: "rejected")
    verify_session!

    get shared_shortlist_path(@shortlist.token)

    assert_response :success
    assert_match "Declined Person", response.body
  end

  # ── download_cv ───────────────────────────────────────────────────────────

  def make_job_role
    JobRole.create!(
      organization: @user.organization, user: @user,
      title: "Test Role", experience_level: "mid",
      required_skills: "skill", responsibilities: "resp"
    )
  end

  test "download_cv redirects to blob URL when ActiveStorage CV is attached" do
    cv = CvAnalysis.create!(
      organization: @user.organization, user: @user, job_role: make_job_role,
      candidate_name: "AS Candidate", drive_file_id: "placeholder"
    )
    cv.cv.attach(io: StringIO.new("PDF content"), filename: "cv.pdf", content_type: "application/pdf")
    item = ShortlistItem.create!(shortlist: @shortlist, cv_analysis: cv, client_status: "pending")
    verify_session!

    get shared_shortlist_cv_path(@shortlist.token, item)

    assert_response :redirect
    assert_match "active_storage", response.location
  end

  test "download_cv routes to drive proxy when drive_file_id is present and no AS attachment" do
    cv = CvAnalysis.create!(
      organization: @user.organization, user: @user, job_role: make_job_role,
      candidate_name: "Drive Candidate", drive_file_id: "fake-drive-id-123"
    )
    item = ShortlistItem.create!(shortlist: @shortlist, cv_analysis: cv, client_status: "pending")
    verify_session!

    get shared_shortlist_cv_path(@shortlist.token, item)

    # stream_drive_cv is reached; fresh_google_access_token returns nil in test
    # (no google_refresh_token on test users) → redirects with Google auth alert
    assert_response :redirect
    assert_match "Google authorization", flash[:alert]
  end

  test "stream_drive_cv streams Drive response with correct content type on success" do
    @user.update_columns(
      google_refresh_token:    "fake-refresh",
      google_access_token:     "fake-access-token",
      google_token_expires_at: 1.hour.from_now
    )
    cv = CvAnalysis.create!(
      organization: @user.organization, user: @user, job_role: make_job_role,
      candidate_name: "Drive Success Candidate", drive_file_id: "drive-id-xyz"
    )
    item = ShortlistItem.create!(shortlist: @shortlist, cv_analysis: cv, client_status: "pending")
    verify_session!

    fake_response = Object.new
    fake_response.define_singleton_method(:code) { "200" }
    fake_response.define_singleton_method(:[]) { |key| key == "Content-Type" ? "application/pdf" : nil }
    fake_response.define_singleton_method(:body) { "PDF byte content" }

    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) { |_req, &blk| blk.call(fake_response) }

    # Temporarily override Net::HTTP.new so no real socket is opened.
    # remove_method in ensure restores the inherited Class#new.
    Net::HTTP.define_singleton_method(:new) { |*_| fake_http }
    begin
      get shared_shortlist_cv_path(@shortlist.token, item)
      assert_response :success
      assert_equal "application/pdf", response.content_type
      assert_equal "PDF byte content", response.body
    ensure
      Net::HTTP.singleton_class.remove_method(:new)
    end
  end

  test "download_cv redirects with alert when no CV is available" do
    verify_session!

    get shared_shortlist_cv_path(@shortlist.token, @item)

    assert_redirected_to shared_shortlist_item_path(@shortlist.token, @item)
    assert_equal "No CV file available.", flash[:alert]
  end

  # ── feedback pipeline sync ────────────────────────────────────────────────

  test "feedback approved advances candidate to final_interview" do
    @candidate.update_columns(pipeline_stage: "client_interview")
    @item.update_columns(client_status: "pending")
    verify_session!

    patch shared_shortlist_feedback_path(@shortlist.token, @item),
          params: { client_status: "approved" }

    assert_equal "final_interview", @candidate.reload.pipeline_stage
  end

  test "feedback rejected moves candidate to not_selected" do
    verify_session!

    patch shared_shortlist_feedback_path(@shortlist.token, @item),
          params: { client_status: "rejected" }

    assert_equal "not_selected", @candidate.reload.pipeline_stage
  end

  test "feedback pending returns candidate to client_interview" do
    verify_session!

    patch shared_shortlist_feedback_path(@shortlist.token, @item),
          params: { client_status: "pending" }

    assert_equal "client_interview", @candidate.reload.pipeline_stage
  end

  test "feedback pipeline sync does not re-trigger after_save callback" do
    second_shortlist = Shortlist.create!(
      user:         @user,
      organization: @user.organization,
      title:        "Second",
      client_email: "other@test.com"
    )
    second_item = ShortlistItem.create!(
      shortlist:     second_shortlist,
      candidate:     @candidate,
      client_status: "rejected"
    )
    verify_session!

    patch shared_shortlist_feedback_path(@shortlist.token, @item),
          params: { client_status: "approved" }

    # after_save would have overwritten second_item to "approved" — it must not
    assert_equal "rejected", second_item.reload.client_status
  end
end
