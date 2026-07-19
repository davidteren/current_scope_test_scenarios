require "test_helper"

# Probe 6: skip_before_action :current_scope_check!, only: [:dashboard] as the
# incremental-adoption escape hatch.
class PartialSkipTest < ActionDispatch::IntegrationTest
  setup do
    @roleless = User.create!(name: "NoRole Ned", email: "ned@example.com")
    CurrentScope.seed_defaults!
  end

  test "the skipped action works for any signed-in user; siblings stay gated" do
    login_as @roleless
    get "/legacy/dashboard"
    assert_response :success

    get "/legacy/stats"
    assert_response :forbidden
  end

  test "the skipped action still runs the host's own require_login" do
    get "/legacy/dashboard"
    assert_redirected_to sessions_path
  end

  test "subclass re-enables the gate so parent skip does not fail-open legacy_sub#dashboard" do
    # Parent skips only :dashboard; Rails inherits the skip. LegacySubController
    # re-registers current_scope_check! for :dashboard so legacy_sub#dashboard
    # (a different permission key) stays enforced (ie-audit P1 / F5 host fix).
    login_as @roleless
    get "/legacy_sub/dashboard"
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]

    get "/legacy_sub/stats"
    assert_response :forbidden
  end
end
