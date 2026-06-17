require "test_helper"

class SyncCalendarTokenTest < ActionDispatch::IntegrationTest
  setup do
    @user = build_user(email: "owner@example.com")
    @user.update!(
      role:                    "owner",
      google_access_token:     "tok",
      google_refresh_token:    "ref",
      google_token_expires_at: 2.hours.from_now
    )
    org = @user.organization

    @candidate = org.candidates.create!(
      name:           "Test Candidate",
      user:           @user,
      pipeline_stage: "cv_review"
    )
    SlotBooking.create!(
      user:      @user,
      candidate: @candidate,
      starts_at: 1.day.from_now,
      ends_at:   1.day.from_now + 30.minutes
    )
  end

  test "sync_calendar redirects to settings with reconnect message when token is revoked" do
    sign_in @user
    stub_calendar_service { raise User::GoogleTokenRevoked, "invalid_grant" }

    post sync_calendar_candidate_path(@candidate)

    assert_redirected_to settings_path
    assert_match "reconnect", flash[:alert].downcase
  end

  test "sync_calendar redirects to candidate page for other calendar errors" do
    sign_in @user
    stub_calendar_service { raise "Calendar API error (500): internal error" }

    post sync_calendar_candidate_path(@candidate)

    assert_redirected_to candidate_path(@candidate)
    assert_match "Could not sync calendar", flash[:alert]
  end

  test "sync_calendar handles InsufficientScopeError on the candidate page" do
    sign_in @user
    stub_calendar_service { raise CalendarEventService::InsufficientScopeError }

    post sync_calendar_candidate_path(@candidate)

    assert_redirected_to candidate_path(@candidate)
    assert_match "permission missing", flash[:alert]
  end

  private

  def stub_calendar_service(&raise_block)
    fake_service = Object.new
    fake_service.define_singleton_method(:call, &raise_block)
    CalendarEventService.define_singleton_method(:new) { |**_| fake_service }
  end

  def teardown
    CalendarEventService.singleton_class.remove_method(:new) rescue nil
  end
end
