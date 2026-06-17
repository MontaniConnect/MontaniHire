require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = build_user(email: "owner@example.com")
    @owner.update!(role: "owner")
    @org = @owner.organization

    @member = build_user(email: "member@example.com")
    @member.update!(organization: @org, role: "member")
  end

  test "owner can update organisation name" do
    sign_in @owner
    patch update_organization_settings_path,
          params: { organization: { name: "New Name", logo_url: "" } }
    assert_redirected_to settings_path
    assert_equal "New Name", @org.reload.name
  end

  test "owner can update logo url" do
    sign_in @owner
    patch update_organization_settings_path,
          params: { organization: { name: @org.name, logo_url: "https://example.com/logo.png" } }
    assert_redirected_to settings_path
    assert_equal "https://example.com/logo.png", @org.reload.logo_url
  end

  test "member cannot update organisation" do
    sign_in @member
    patch update_organization_settings_path,
          params: { organization: { name: "Hacked" } }
    assert_redirected_to root_path
    assert_not_equal "Hacked", @org.reload.name
  end

  test "unauthenticated user cannot update organisation" do
    patch update_organization_settings_path,
          params: { organization: { name: "Hacked" } }
    assert_redirected_to login_path
  end

  test "invalid logo URL is rejected with error flash" do
    sign_in @owner
    patch update_organization_settings_path,
          params: { organization: { name: @org.name, logo_url: "http://insecure.com/logo.png" } }
    assert_redirected_to settings_path
    assert_match "HTTPS", flash[:alert]
    assert_nil @org.reload.logo_url
  end

  test "valid HTTPS logo URL is accepted" do
    sign_in @owner
    patch update_organization_settings_path,
          params: { organization: { name: @org.name, logo_url: "https://example.com/logo.png" } }
    assert_redirected_to settings_path
    assert_equal "https://example.com/logo.png", @org.reload.logo_url
  end
end
