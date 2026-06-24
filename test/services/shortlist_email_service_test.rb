require "test_helper"

class ShortlistEmailServiceTest < ActiveSupport::TestCase
  FakeShortlist = Struct.new(:title, :user, keyword_init: true)

  def decision_shortlist(title: "Ops Role", recruiter_email: "recruiter@example.com", recruiter_name: "Ana Santos")
    user = Struct.new(:email, :name).new(recruiter_email, recruiter_name)
    FakeShortlist.new(title: title, user: user)
  end

  # ── nil role_name fallback ────────────────────────────────────────────────

  test "decision_url subject uses 'this position' when role_name is nil" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: [],
      role_name:      nil
    )
    assert_includes url, ERB::Util.url_encode("this position")
  end

  # ── URL structure ─────────────────────────────────────────────────────────

  test "decision_url returns a Gmail compose URL" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: ["Ana R."],
      role_name:      "Operations Manager"
    )
    assert_match %r{\Ahttps://mail\.google\.com/mail/\?view=cm}, url
  end

  # ── Subject ───────────────────────────────────────────────────────────────

  test "decision_url subject contains role name and Interview Availability" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: [],
      role_name:      "Sales Associate"
    )
    assert_includes url, ERB::Util.url_encode("Sales Associate")
    assert_includes url, ERB::Util.url_encode("Interview Availability")
  end

  # ── To: address ───────────────────────────────────────────────────────────

  test "decision_url TO contains recruiter email" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      role_name:      "Ops"
    )
    assert_includes url, ERB::Util.url_encode("recruiter@montani.ph")
  end

  test "decision_url TO contains OPS_EMAIL when set" do
    original = ENV["OPS_EMAIL"]
    ENV["OPS_EMAIL"] = "ops@montani.ph"

    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      role_name:      "Ops"
    )
    assert_includes url, ERB::Util.url_encode("recruiter@montani.ph,ops@montani.ph")
  ensure
    ENV["OPS_EMAIL"] = original
  end

  test "decision_url handles blank OPS_EMAIL gracefully — TO is recruiter only" do
    original = ENV["OPS_EMAIL"]
    ENV["OPS_EMAIL"] = ""

    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      role_name:      "Ops"
    )
    assert_includes url, "to=#{ERB::Util.url_encode('recruiter@montani.ph')}"
    refute_includes url, ","
  ensure
    ENV["OPS_EMAIL"] = original
  end

  # ── Body ──────────────────────────────────────────────────────────────────

  test "decision_url body includes selected candidate names" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: ["Ana R.", "Ben T."],
      role_name:      "Ops"
    )
    assert_includes url, ERB::Util.url_encode("Ana R.")
    assert_includes url, ERB::Util.url_encode("Ben T.")
  end

  test "decision_url body addresses recruiter by name" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist(recruiter_name: "Maria Santos"),
      selected_names: [],
      role_name:      "Ops"
    )
    assert_includes url, ERB::Util.url_encode("Maria Santos")
  end

  test "decision_url body includes placeholder availability slots" do
    url = ShortlistEmailService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: [],
      role_name:      "Ops"
    )
    assert_includes url, ERB::Util.url_encode("dates and times I have available")
  end
end
