require "test_helper"

class GmailComposeUrlServiceTest < ActiveSupport::TestCase
  FakeRole      = Struct.new(:title, keyword_init: true)
  FakeOrg       = Struct.new(:name, keyword_init: true)
  FakeUser      = Struct.new(:organization, keyword_init: true)
  FakeCandidate = Struct.new(:email, :first_name, :job_role, :user, keyword_init: true)

  def service(email: "ana@example.com", first_name: "Ana", role_title: "Operations Manager", org_name: "TestCo")
    role      = role_title ? FakeRole.new(title: role_title) : nil
    org       = org_name ? FakeOrg.new(name: org_name) : nil
    user      = FakeUser.new(organization: org)
    candidate = FakeCandidate.new(email: email, first_name: first_name, job_role: role, user: user)
    GmailComposeUrlService.new(candidate: candidate)
  end

  INTAKE_URL = "https://app.example.com/i/abc123"

  # ── URL structure ──────────────────────────────────────────────────────────

  test "invite_url returns a Gmail compose URL" do
    url = service.invite_url(INTAKE_URL)
    assert_match %r{\Ahttps://mail\.google\.com/mail/\?view=cm}, url
  end

  test "followup_url returns a Gmail compose URL" do
    url = service.followup_url(INTAKE_URL)
    assert_match %r{\Ahttps://mail\.google\.com/mail/\?view=cm}, url
  end

  # ── To: address ───────────────────────────────────────────────────────────

  test "invite_url encodes the candidate email in to=" do
    url = service(email: "ana+test@example.com").invite_url(INTAKE_URL)
    assert_includes url, "to=ana%2Btest%40example.com"
  end

  test "followup_url encodes the candidate email in to=" do
    url = service(email: "ana+test@example.com").followup_url(INTAKE_URL)
    assert_includes url, "to=ana%2Btest%40example.com"
  end

  # ── Subject lines ─────────────────────────────────────────────────────────

  test "invite_url subject contains role title" do
    url = service(role_title: "Operations Manager").invite_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Operations Manager")
  end

  test "invite_url subject contains 'Preliminary Interview Invitation'" do
    url = service.invite_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Preliminary Interview Invitation")
  end

  test "followup_url subject starts with 'Following up'" do
    url = service.followup_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Following up")
  end

  test "followup_url subject contains role title" do
    url = service(role_title: "Operations Manager").followup_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Operations Manager")
  end

  # ── nil job role fallback ─────────────────────────────────────────────────

  test "invite_url uses 'this position' when job_role is nil" do
    url = service(role_title: nil).invite_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("this position")
  end

  test "followup_url uses 'this position' when job_role is nil" do
    url = service(role_title: nil).followup_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("this position")
  end

  # ── Body includes intake URL ───────────────────────────────────────────────

  test "invite_url body includes the intake URL" do
    url = service.invite_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode(INTAKE_URL)
  end

  test "followup_url body includes the intake URL" do
    url = service.followup_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode(INTAKE_URL)
  end

  # ── Body personalisation ──────────────────────────────────────────────────

  test "invite_url body addresses candidate by first name" do
    url = service(first_name: "Ana").invite_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Ana")
  end

  test "followup_url body addresses candidate by first name" do
    url = service(first_name: "Ana").followup_url(INTAKE_URL)
    assert_includes url, ERB::Util.url_encode("Ana")
  end

  # ── invite vs followup are distinct ──────────────────────────────────────

  test "invite_url and followup_url produce different subjects" do
    svc = service
    assert_not_equal svc.invite_url(INTAKE_URL), svc.followup_url(INTAKE_URL)
  end

  # ── decision_url ─────────────────────────────────────────────────────────

  FakeShortlist = Struct.new(:title, :user, :client_availability, keyword_init: true)

  def decision_shortlist(title: "Ops Role", recruiter_email: "recruiter@example.com", availability: "Mon–Fri 9 AM EST")
    user = Struct.new(:email).new(recruiter_email)
    FakeShortlist.new(title: title, user: user, client_availability: availability)
  end

  test "decision_url returns a Gmail compose URL" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: ["Ana R."],
      declined_names: []
    )
    assert_match %r{\Ahttps://mail\.google\.com/mail/\?view=cm}, url
  end

  test "decision_url subject contains shortlist title" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist(title: "Sales Associate"),
      selected_names: [],
      declined_names: []
    )
    assert_includes url, ERB::Util.url_encode("Sales Associate")
    assert_includes url, ERB::Util.url_encode("Final Interview Decision")
  end

  test "decision_url TO contains recruiter email" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      declined_names: []
    )
    assert_includes url, ERB::Util.url_encode("recruiter@montani.ph")
  end

  test "decision_url TO contains OPS_EMAIL when set" do
    ClimateControl.module_eval {} rescue nil  # no climate_control gem — use ENV directly
    original = ENV["OPS_EMAIL"]
    ENV["OPS_EMAIL"] = "ops@montani.ph"

    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      declined_names: []
    )
    assert_includes url, ERB::Util.url_encode("recruiter@montani.ph,ops@montani.ph")
  ensure
    ENV["OPS_EMAIL"] = original
  end

  test "decision_url handles blank OPS_EMAIL gracefully — TO is recruiter only" do
    original = ENV["OPS_EMAIL"]
    ENV["OPS_EMAIL"] = ""

    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist(recruiter_email: "recruiter@montani.ph"),
      selected_names: [],
      declined_names: []
    )
    assert_includes url, "to=#{ERB::Util.url_encode('recruiter@montani.ph')}"
    refute_includes url, ","
  ensure
    ENV["OPS_EMAIL"] = original
  end

  test "decision_url body includes selected candidate names" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: ["Ana R.", "Ben T."],
      declined_names: []
    )
    assert_includes url, ERB::Util.url_encode("Ana R.")
    assert_includes url, ERB::Util.url_encode("Ben T.")
  end

  test "decision_url body includes declined candidate names" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist,
      selected_names: [],
      declined_names: ["Maria S."]
    )
    assert_includes url, ERB::Util.url_encode("Maria S.")
  end

  test "decision_url body includes availability text" do
    url = GmailComposeUrlService.decision_url(
      shortlist:      decision_shortlist(availability: "Mon–Fri 9 AM EST"),
      selected_names: [],
      declined_names: []
    )
    assert_includes url, ERB::Util.url_encode("Mon–Fri 9 AM EST")
  end
end
