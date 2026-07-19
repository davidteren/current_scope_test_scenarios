require "test_helper"

# Probe 1: the big-bang retrofit story. Guard was bolted onto a working
# logged-in-only legacy app. This documents what a legacy team hits first.
class LegacyRetrofitTest < ActionDispatch::IntegrationTest
  setup do
    @roleless = User.create!(name: "Roleless Rita", email: "rita@example.com")
    @owner = User.create!(name: "Owner Olga", email: "olga@example.com")
    make_owner!(@owner)
  end

  test "WALL 1: logged-out users get a bare 403, not the app's login redirect" do
    # Pre-gem: GET /legacy/stats redirected to the login page.
    # Post-gem: Guard's before_action registered at include time runs BEFORE
    # the host's own `before_action :require_login` (declared after the
    # includes, per the README's own install snippet), so anonymous users get
    # 403 instead of the login redirect. Auth UX silently broken.
    get "/legacy/stats"
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "WALL 2: every gated action 403s for every signed-in user until roles exist" do
    login_as @roleless
    get "/legacy/stats";          assert_response :forbidden
    get "/legacy/export_csv";     assert_response :forbidden
    post "/legacy/import";        assert_response :forbidden
    post "/legacy/approve_all";   assert_response :forbidden
    get "/legacy/settings";       assert_response :forbidden
  end

  test "an unrescued denial is a 403 with an EMPTY body (gem self-rescues), not a 500" do
    login_as @roleless
    get "/legacy/stats"
    assert_response :forbidden
    assert_equal "", response.body.to_s
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
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
