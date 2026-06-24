require "test_helper"

class ShortlistsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user  = build_user
    @org   = @user.organization
    @adder = build_user
    @adder.update!(organization: @org, name: "Added By Tester")

    @shortlist = Shortlist.create!(
      user:         @user,
      organization: @org,
      title:        "Test Shortlist",
      client_email: "hm@test.com"
    )
    @candidate = Candidate.create!(
      user:           @user,
      organization:   @org,
      name:           "Jane Doe",
      pipeline_stage: "cv_review"
    )
    @item = ShortlistItem.create!(
      shortlist:     @shortlist,
      candidate:     @candidate,
      added_by:      @adder,
      client_status: "pending"
    )
  end

  test "show renders 200 for the owning org" do
    sign_in @user
    get shortlist_path(@shortlist)
    assert_response :success
  end

  test "show includes the added_by name in the rendered output" do
    sign_in @user
    get shortlist_path(@shortlist)
    assert_match "Added By Tester", response.body
  end

  test "show redirects when the shortlist belongs to a different org" do
    other_user = build_user
    sign_in other_user
    get shortlist_path(@shortlist)
    assert_redirected_to shortlists_path
    assert_match "not found", flash[:alert]
  end
end
