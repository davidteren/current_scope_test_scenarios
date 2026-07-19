require "test_helper"

# Probe 1: the big-bang retrofit story. Guard was bolted onto a working
# logged-in-only legacy app. This documents what a legacy team hits first.
class LegacyRetrofitTest < ActionDispatch::IntegrationTest
  setup do
    @roleless = User.create!(name: "Roleless Rita", email: "rita@example.com")
    @owner = User.create!(name: "Owner Olga", email: "olga@example.com")
    make_owner!(@owner)
  end

  test "logged-out users hit require_login before Guard and redirect to sign-in" do
    # Host fix for F2 / ie-audit P1: require_login is registered before Guard
    # is included, so anonymous traffic gets the login redirect instead of a
    # bare 403 from current_scope_check!.
    get "/legacy/stats"
    assert_redirected_to sessions_path
    follow_redirect!
    assert_includes response.body, "Log in first"
  end

  test "WALL 2: every gated action 403s for every signed-in user until roles exist" do
    login_as @roleless
    get "/legacy/stats";          assert_response :forbidden
    get "/legacy/export_csv";     assert_response :forbidden
    post "/legacy/import";        assert_response :forbidden
    post "/legacy/approve_all";   assert_response :forbidden
    get "/legacy/settings";       assert_response :forbidden
  end

  test "a denial renders a host 403 page with reason header, not an empty body" do
    login_as @roleless
    get "/legacy/stats"
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_includes response.body, "Access denied"
    assert_includes response.body, "no_grant"
    assert_select "#access-denied"
  end

  test "turbo_stream negotiated denials also render the host 403 page" do
    login_as @roleless
    get "/legacy/settings",
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_includes response.body, "Access denied"
  end


  test "full-access owner passes everywhere" do
    login_as @owner
    get "/legacy/stats";          assert_response :success
    get "/legacy/export_csv";     assert_response :success
    post "/legacy/import";        assert_response :redirect
    get "/legacy/settings";       assert_response :success
  end

  # 0.3.0: F1 fixed — report mode is the observe-first adoption ramp this
  # scenario was missing. config.enforcement = :report lets a would-be
  # :no_grant denial THROUGH, marks it X-Current-Scope-Reason: would_deny, and
  # records an access.would_deny ledger event (bin/rails current_scope:report
  # summarizes them). Default stays :enforce, so the 0.2.0 walls above are
  # unchanged unless a team opts in.
  test "0.3.0: enforcement = :report observes no_grant denials instead of enforcing them" do
    assert_equal :enforce, CurrentScope.config.enforcement # default unchanged

    CurrentScope.config.enforcement = :report
    login_as @roleless
    get "/legacy/stats"
    assert_response :success
    assert_equal "would_deny", response.headers["X-Current-Scope-Reason"]
    assert CurrentScope::Event.exists?(event: "access.would_deny"),
           "expected the would-be denial to be recorded to the ledger"
  ensure
    CurrentScope.config.enforcement = :enforce
  end
end
