require "test_helper"
require "rack/mock_request"

class RackAttackTest < ActionDispatch::IntegrationTest
  # Sends a request through Rack::Attack middleware only — bypasses Rails routing.
  # The inner app always returns 200 so the only source of 429 is Rack::Attack itself.
  def throttle_req(path, user_id:, method: "POST", accept: "text/html")
    env = Rack::MockRequest.env_for(path,
      method:        method,
      "rack.session" => { "user_id" => user_id },
      "HTTP_ACCEPT"  => accept
    )
    status, = Rack::Attack.new(->(e) { [200, {}, []] }).call(env)
    status
  end

  setup do
    Rack::Attack.reset!
  end

  # ── cv_analysis/user ──────────────────────────────────────────────────────

  test "cv_analyses/create is throttled after 10 requests per user per hour" do
    user_id = 888_001
    10.times { assert_equal 200, throttle_req("/cv_analyses", user_id: user_id) }
    assert_equal 429, throttle_req("/cv_analyses", user_id: user_id)
  end

  test "cv_analyses/bulk_create is throttled after 10 requests per user per hour" do
    user_id = 888_002
    10.times { assert_equal 200, throttle_req("/cv_analyses/bulk_create", user_id: user_id) }
    assert_equal 429, throttle_req("/cv_analyses/bulk_create", user_id: user_id)
  end

  # ── video_analysis/user ───────────────────────────────────────────────────

  test "video_analyses/create is throttled after 10 requests per user per hour" do
    user_id = 888_003
    10.times { assert_equal 200, throttle_req("/video_analyses", user_id: user_id) }
    assert_equal 429, throttle_req("/video_analyses", user_id: user_id)
  end

  # ── reanalysis/analysis ───────────────────────────────────────────────────

  test "reanalyse is throttled after 3 requests per analysis per hour" do
    user_id = 888_004
    3.times { assert_equal 200, throttle_req("/cv_analyses/42/reanalyse", user_id: user_id) }
    assert_equal 429, throttle_req("/cv_analyses/42/reanalyse", user_id: user_id)
  end

  test "reanalyse throttle is scoped per analysis ID — different ID is not throttled" do
    user_id = 888_005
    3.times { throttle_req("/cv_analyses/100/reanalyse", user_id: user_id) }
    assert_equal 200, throttle_req("/cv_analyses/200/reanalyse", user_id: user_id)
  end

  test "video reanalyse is throttled independently from cv reanalyse" do
    user_id = 888_006
    3.times { throttle_req("/cv_analyses/55/reanalyse", user_id: user_id) }
    # Same analysis numeric ID on video path — separate throttle key
    assert_equal 200, throttle_req("/video_analyses/55/reanalyse", user_id: user_id)
  end

  # ── claude_calls/org billing backstop ────────────────────────────────────

  test "claude_calls/org throttle fires after 50 requests from same org" do
    user_a = build_user
    user_b = build_user
    user_b.update!(organization: user_a.organization)
    org_id = user_a.organization_id

    # Both users share the same org — their requests count together
    25.times { throttle_req("/cv_analyses", user_id: user_a.id) }
    25.times { throttle_req("/cv_analyses", user_id: user_b.id) }
    # 51st request from either user in this org — should be throttled by the org rule
    assert_equal 429, throttle_req("/cv_analyses", user_id: user_a.id)
  end

  # ── user isolation ────────────────────────────────────────────────────────

  test "user A throttle does not affect user B" do
    user_a = 888_007
    user_b = 888_008
    10.times { throttle_req("/cv_analyses", user_id: user_a) }
    assert_equal 429, throttle_req("/cv_analyses", user_id: user_a)
    assert_equal 200, throttle_req("/cv_analyses", user_id: user_b)
  end

  # ── super_admin safelist ──────────────────────────────────────────────────

  test "super_admin is not throttled on analysis paths" do
    admin = build_user
    admin.update!(role: "super_admin")
    statuses = 11.times.map { throttle_req("/cv_analyses", user_id: admin.id) }
    assert statuses.all? { |s| s == 200 }, "Expected all 200, got: #{statuses.inspect}"
  end

  test "regular user is throttled at the same paths super_admin is not" do
    regular = build_user
    10.times { throttle_req("/cv_analyses", user_id: regular.id) }
    assert_equal 429, throttle_req("/cv_analyses", user_id: regular.id)
  end

  # ── health check safelist ─────────────────────────────────────────────────

  test "health check path /up is never throttled" do
    assert_equal 200, throttle_req("/up", user_id: nil, method: "GET")
  end

  # ── 429 response format ───────────────────────────────────────────────────

  test "throttled JSON request returns 429 with error JSON body" do
    user_id = 888_009
    10.times { throttle_req("/cv_analyses", user_id: user_id) }

    env = Rack::MockRequest.env_for("/cv_analyses",
      method:        "POST",
      "rack.session" => { "user_id" => user_id },
      "HTTP_ACCEPT"  => "application/json"
    )
    status, headers, body = Rack::Attack.new(->(e) { [200, {}, []] }).call(env)
    assert_equal 429, status
    assert_equal "application/json", headers["Content-Type"]
    assert_includes body.join, "Too many requests"
  end

  test "throttled HTML request returns 429 with HTML body" do
    user_id = 888_010
    10.times { throttle_req("/cv_analyses", user_id: user_id) }

    env = Rack::MockRequest.env_for("/cv_analyses",
      method:        "POST",
      "rack.session" => { "user_id" => user_id },
      "HTTP_ACCEPT"  => "text/html"
    )
    status, headers, body = Rack::Attack.new(->(e) { [200, {}, []] }).call(env)
    assert_equal 429, status
    assert_equal "text/html", headers["Content-Type"]
    assert_includes body.join, "Too many requests"
  end

  # ── non-analysis paths are not throttled ─────────────────────────────────

  test "non-analysis GET requests are not throttled" do
    user_id = 888_011
    # candidates index — not an analysis path, should never throttle
    11.times.each do
      assert_equal 200, throttle_req("/candidates", user_id: user_id, method: "GET")
    end
  end
end
