require "test_helper"

class LogoUrlValidationTest < ActiveSupport::TestCase
  # ── Organization#logo_url ───────────────────────────────────────────────────

  test "org: blank logo_url is valid" do
    org = Organization.new(name: "Test Org", logo_url: "")
    org.valid?
    assert_empty org.errors[:logo_url]
  end

  test "org: nil logo_url is valid" do
    org = Organization.new(name: "Test Org", logo_url: nil)
    org.valid?
    assert_empty org.errors[:logo_url]
  end

  test "org: valid HTTPS image URL is accepted" do
    %w[
      https://example.com/logo.png
      https://cdn.example.com/images/logo.jpg
      https://example.com/logo.webp?v=2
      https://example.com/logo.SVG
    ].each do |url|
      org = Organization.new(name: "Test Org", logo_url: url)
      org.valid?
      assert_empty org.errors[:logo_url], "Expected #{url} to be valid"
    end
  end

  test "org: HTTP URL is rejected" do
    org = Organization.new(name: "Test Org", logo_url: "http://example.com/logo.png")
    org.valid?
    assert_includes org.errors[:logo_url], ValidatesLogoUrl::LOGO_URL_MESSAGE
  end

  test "org: non-image extension is rejected" do
    org = Organization.new(name: "Test Org", logo_url: "https://example.com/logo.pdf")
    org.valid?
    assert_includes org.errors[:logo_url], ValidatesLogoUrl::LOGO_URL_MESSAGE
  end

  test "org: URL without extension is rejected" do
    org = Organization.new(name: "Test Org", logo_url: "https://cdn.example.com/logo")
    org.valid?
    assert_includes org.errors[:logo_url], ValidatesLogoUrl::LOGO_URL_MESSAGE
  end

  test "org: plain string is rejected" do
    org = Organization.new(name: "Test Org", logo_url: "not-a-url")
    org.valid?
    assert_includes org.errors[:logo_url], ValidatesLogoUrl::LOGO_URL_MESSAGE
  end

  # ── Client#logo_url ─────────────────────────────────────────────────────────

  setup do
    @owner = build_user
    @org   = @owner.organization
  end

  def new_client(logo_url)
    Client.new(organization: @org, name: "Acme Corp", logo_url: logo_url)
  end

  test "client: blank logo_url is valid" do
    assert new_client("").valid?
  end

  test "client: valid HTTPS image URL is accepted" do
    assert new_client("https://example.com/logo.png").valid?
  end

  test "client: HTTP URL is rejected" do
    cl = new_client("http://example.com/logo.png")
    cl.valid?
    assert cl.errors[:logo_url].any?
  end

  test "client: non-image extension is rejected" do
    cl = new_client("https://example.com/logo.exe")
    cl.valid?
    assert cl.errors[:logo_url].any?
  end
end
