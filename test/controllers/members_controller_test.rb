require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = build_user(email: "owner@example.com")
    @org   = @owner.organization
    @owner.update!(role: "owner")

    @member = build_user(email: "member@example.com")
    @member.update!(organization: @org, role: "member")

    @viewer = build_user(email: "viewer@example.com")
    @viewer.update!(organization: @org, role: "viewer")
  end

  # ── removal ──────────────────────────────────────────────────────────────────

  test "owner can remove a member" do
    sign_in @owner
    assert_difference -> { @org.users.count }, -1 do
      delete member_path(@member)
    end
    assert_redirected_to settings_path
    assert_match "removed", flash[:notice]
    @member.reload
    assert_nil @member.organization_id
  end

  test "owner can remove a viewer" do
    sign_in @owner
    delete member_path(@viewer)
    assert_redirected_to settings_path
    @viewer.reload
    assert_nil @viewer.organization_id
  end

  test "sole owner cannot remove themselves" do
    sign_in @owner
    delete member_path(@owner)
    assert_redirected_to settings_path
    assert_match "only owner", flash[:alert]
    @owner.reload
    assert_equal @org, @owner.organization
  end

  test "owner with a co-owner CAN remove themselves" do
    co_owner = build_user(email: "co@example.com")
    co_owner.update!(organization: @org, role: "owner")

    sign_in @owner
    delete member_path(@owner)
    assert_redirected_to settings_path
    assert_nil flash[:alert]
    @owner.reload
    assert_nil @owner.organization_id
  end

  test "member cannot remove anyone" do
    sign_in @member
    delete member_path(@viewer)
    assert_redirected_to root_path
  end

  test "cannot remove a member from a different org" do
    other_user = build_user(email: "other@example.com")
    sign_in @owner
    delete member_path(other_user)
    assert_redirected_to settings_path
    assert_match "not found", flash[:alert]
  end

  # ── role change ───────────────────────────────────────────────────────────────

  test "owner can demote a member to viewer" do
    sign_in @owner
    patch member_path(@member), params: { role: "viewer" }
    assert_redirected_to settings_path
    assert_equal "viewer", @member.reload.role
  end

  test "owner can promote a viewer to member" do
    sign_in @owner
    patch member_path(@viewer), params: { role: "member" }
    assert_redirected_to settings_path
    assert_equal "member", @viewer.reload.role
  end

  test "rejects invalid role values" do
    sign_in @owner
    patch member_path(@member), params: { role: "owner" }
    assert_redirected_to settings_path
    assert_match "Invalid role", flash[:alert]
    assert_equal "member", @member.reload.role
  end

  test "sole owner cannot change their own role" do
    sign_in @owner
    patch member_path(@owner), params: { role: "member" }
    assert_redirected_to settings_path
    assert_match "only owner", flash[:alert]
    assert_equal "owner", @owner.reload.role
  end

  test "owner with co-owner CAN change their own role" do
    co_owner = build_user(email: "co2@example.com")
    co_owner.update!(organization: @org, role: "owner")

    sign_in @owner
    patch member_path(@owner), params: { role: "member" }
    assert_redirected_to settings_path
    assert_equal "member", @owner.reload.role
  end

  test "viewer cannot change roles" do
    sign_in @viewer
    patch member_path(@member), params: { role: "viewer" }
    assert_redirected_to root_path
  end
end
