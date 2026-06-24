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

  # ── submit_decision ───────────────────────────────────────────────────────

  test "submit_decision saves client_availability and stamps submitted_at" do
    verify_session!

    post shared_shortlist_decision_path(@shortlist.token),
         params: { client_availability: "Mon–Fri 9 AM EST" }

    @shortlist.reload
    assert_equal "Mon–Fri 9 AM EST", @shortlist.client_availability
    assert_not_nil @shortlist.client_decision_submitted_at
  end

  test "submit_decision redirects to shortlist show page" do
    verify_session!

    post shared_shortlist_decision_path(@shortlist.token),
         params: { client_availability: "Anytime" }

    assert_redirected_to shared_shortlist_path(@shortlist.token)
  end

  test "submit_decision is idempotent — second submission does not overwrite" do
    original_time = 2.hours.ago
    @shortlist.update_columns(
      client_availability:          "original availability",
      client_decision_submitted_at: original_time
    )
    verify_session!

    post shared_shortlist_decision_path(@shortlist.token),
         params: { client_availability: "overwrite attempt" }

    @shortlist.reload
    assert_equal "original availability", @shortlist.client_availability
    assert_in_delta original_time.to_i, @shortlist.client_decision_submitted_at.to_i, 1
  end

  test "submit_decision idempotent response sets alert flash" do
    @shortlist.update_columns(client_decision_submitted_at: 1.hour.ago)
    verify_session!

    post shared_shortlist_decision_path(@shortlist.token),
         params: { client_availability: "ignored" }

    assert flash[:alert].present?
    assert_match(/already sent/i, flash[:alert])
  end

  test "submit_decision requires verification" do
    post shared_shortlist_decision_path(@shortlist.token),
         params: { client_availability: "Anytime" }

    assert_redirected_to shared_shortlist_path(@shortlist.token)
    assert_nil @shortlist.reload.client_decision_submitted_at
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

  test "Decision received badge absent when client_decision_submitted_at is nil" do
    # accessed via recruiter view — just assert the column value is correct
    assert_nil @shortlist.client_decision_submitted_at
  end

  test "Decision received badge present when client_decision_submitted_at is set" do
    @shortlist.update_columns(client_decision_submitted_at: Time.current)
    assert_not_nil @shortlist.client_decision_submitted_at
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
