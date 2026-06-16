require "test_helper"

# Covers Auth::GoogleController#callback.
#
# Network calls (exchange_code, decode_id_token) are stubbed at the instance
# level so no real HTTP or JWT parsing occurs.
class Auth::GoogleCallbackTest < ActionDispatch::IntegrationTest
  # ── Helpers ─────────────────────────────────────────────────────────────────

  TOKENS = {
    "access_token"  => "at_test",
    "refresh_token" => "rt_test",
    "expires_in"    => 3600
  }.freeze

  def stub_oauth(controller, tokens: TOKENS, email: "user@example.com", name: "Test User")
    controller.define_singleton_method(:exchange_code) { |_code| tokens }
    controller.define_singleton_method(:decode_id_token) { |_t| { "email" => email, "name" => name } }
  end

  def get_callback(code: "valid_code")
    get auth_google_callback_path, params: { code: code }
  end

  # ── Reconnect path (current_user present) ───────────────────────────────────

  test "reconnect: matching email saves tokens to current_user" do
    user = build_user(email: "user@example.com")
    sign_in user

    Auth::GoogleController.prepend(Module.new do
      define_method(:exchange_code)   { |_| TOKENS }
      define_method(:decode_id_token) { |_| { "email" => "user@example.com", "name" => "Test User" } }
    end)

    get_callback

    user.reload
    assert_equal "at_test", user.google_access_token
    assert_equal "rt_test", user.google_refresh_token
    assert_redirected_to settings_path
    assert_equal "Google account reconnected.", flash[:notice]
  end

  test "reconnect: mismatched email does NOT update current_user tokens" do
    user = build_user(email: "user@example.com")
    user.update_columns(google_access_token: "original_at", google_refresh_token: "original_rt")
    sign_in user

    Auth::GoogleController.prepend(Module.new do
      define_method(:exchange_code)   { |_| TOKENS }
      define_method(:decode_id_token) { |_| { "email" => "other@example.com", "name" => "Other" } }
    end)

    get_callback

    user.reload
    assert_equal "original_at", user.google_access_token,  "access token must not change"
    assert_equal "original_rt", user.google_refresh_token, "refresh token must not change"
  end

  test "reconnect: mismatched email redirects to settings with an alert" do
    user = build_user(email: "user@example.com")
    sign_in user

    Auth::GoogleController.prepend(Module.new do
      define_method(:exchange_code)   { |_| TOKENS }
      define_method(:decode_id_token) { |_| { "email" => "other@example.com", "name" => "Other" } }
    end)

    get_callback

    assert_redirected_to settings_path
    assert_match "other@example.com", flash[:alert]
    assert_match "user@example.com",  flash[:alert]
  end

  # ── Login path (current_user absent) ────────────────────────────────────────

  test "login: new user is registered, session is set, redirected to root" do
    Auth::GoogleController.prepend(Module.new do
      define_method(:exchange_code)   { |_| TOKENS }
      define_method(:decode_id_token) { |_| { "email" => "new@example.com", "name" => "New User" } }
    end)

    assert_difference "User.count", 1 do
      get_callback
    end

    user = User.find_by!(email: "new@example.com")
    assert_equal "at_test", user.google_access_token
    assert_redirected_to root_path
  end

  test "login: returning user is found and tokens are refreshed" do
    existing = build_user(email: "returning@example.com")

    Auth::GoogleController.prepend(Module.new do
      define_method(:exchange_code)   { |_| TOKENS }
      define_method(:decode_id_token) { |_| { "email" => "returning@example.com", "name" => "Returning" } }
    end)

    assert_no_difference "User.count" do
      get_callback
    end

    existing.reload
    assert_equal "at_test", existing.google_access_token
    assert_redirected_to root_path
  end

  test "login: blank code redirects to login with alert" do
    get auth_google_callback_path, params: { code: "" }

    assert_redirected_to login_path
    assert_match "denied or cancelled", flash[:alert]
  end
end
