require "test_helper"

class UserGoogleTokenTest < ActiveSupport::TestCase
  setup do
    @user = build_user
    @user.update!(
      google_refresh_token: "fake_refresh_token",
      google_access_token:  "fake_access_token"
    )
  end

  # ── google_token_fresh? ───────────────────────────────────────────────────────

  test "nil expires_at is treated as expired, not fresh" do
    @user.google_token_expires_at = nil
    assert_not @user.google_token_fresh?
  end

  test "past expires_at is not fresh" do
    @user.google_token_expires_at = 1.hour.ago
    assert_not @user.google_token_fresh?
  end

  test "expires_at within the 5-minute buffer is not fresh" do
    @user.google_token_expires_at = 3.minutes.from_now
    assert_not @user.google_token_fresh?
  end

  test "expires_at beyond 5 minutes is fresh" do
    @user.google_token_expires_at = 10.minutes.from_now
    assert @user.google_token_fresh?
  end

  # ── refresh_google_token! raises on error ────────────────────────────────────

  test "raises GoogleTokenRevoked when Google returns invalid_grant" do
    with_token_response("error" => "invalid_grant", "error_description" => "Token has been expired or revoked.") do
      err = assert_raises(User::GoogleTokenRevoked) { @user.send(:refresh_google_token!) }
      assert_match "invalid_grant", err.message
      assert_match "Token has been expired or revoked", err.message
    end
  end

  test "raises GoogleTokenRevoked for any error key from Google" do
    with_token_response("error" => "invalid_client") do
      assert_raises(User::GoogleTokenRevoked) { @user.send(:refresh_google_token!) }
    end
  end

  test "updates access token on successful refresh" do
    with_token_response("access_token" => "new_access", "expires_in" => 3600) do
      @user.send(:refresh_google_token!)
      assert_equal "new_access", @user.reload.google_access_token
      assert_in_delta Time.current + 3600.seconds, @user.google_token_expires_at, 5.seconds
    end
  end

  # ── nil expires_at triggers a refresh attempt ─────────────────────────────────

  test "nil expires_at causes fresh_google_access_token to attempt refresh" do
    @user.update!(google_token_expires_at: nil)
    refresh_called = false
    @user.define_singleton_method(:refresh_google_token!) { refresh_called = true }

    @user.fresh_google_access_token

    assert refresh_called, "Expected refresh to be attempted when expires_at is nil"
  end

  test "fresh token skips refresh" do
    @user.update!(google_token_expires_at: 1.hour.from_now)
    refresh_called = false
    @user.define_singleton_method(:refresh_google_token!) { refresh_called = true }

    @user.fresh_google_access_token

    assert_not refresh_called
  end

  # ── fresh_google_access_token returns nil without a refresh_token ─────────────

  test "returns nil when no refresh_token is stored" do
    @user.update!(google_refresh_token: nil)
    assert_nil @user.fresh_google_access_token
  end

  private

  def with_token_response(body_hash)
    original_id     = ENV["GOOGLE_CLIENT_ID"]
    original_secret = ENV["GOOGLE_CLIENT_SECRET"]
    ENV["GOOGLE_CLIENT_ID"]     = "fake_client_id"
    ENV["GOOGLE_CLIENT_SECRET"] = "fake_client_secret"

    original = Net::HTTP.method(:post_form)
    fake     = Struct.new(:body).new(body_hash.to_json)
    Net::HTTP.define_singleton_method(:post_form) { |*| fake }
    yield
  ensure
    Net::HTTP.define_singleton_method(:post_form, &original)
    ENV["GOOGLE_CLIENT_ID"]     = original_id
    ENV["GOOGLE_CLIENT_SECRET"] = original_secret
  end
end
