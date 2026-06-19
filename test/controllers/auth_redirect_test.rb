require "test_helper"

# Characterization: every authenticated endpoint must redirect to /login
# when no session is present. These tests document the security boundary
# and must remain green after the org migration.
class AuthRedirectTest < ActionDispatch::IntegrationTest
  AUTHENTICATED_ENDPOINTS = [
    [ :get,    "/candidates"      ],
    [ :get,    "/job_roles"       ],
    [ :get,    "/video_analyses"  ],
    [ :get,    "/cv_analyses"     ],
    [ :get,    "/shortlists"      ],
    [ :get,    "/dashboard"       ],
    [ :get,    "/settings"        ]
  ].freeze

  AUTHENTICATED_ENDPOINTS.each do |verb, path|
    test "#{verb.upcase} #{path} without session redirects to login" do
      public_send(verb, path)
      assert_redirected_to login_path
    end
  end

  test "login page is accessible without a session" do
    get login_path
    assert_response :success
  end
end
