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
    assert_redirected_to "/sessions"
  end

  test "SURPRISE: the parent's partial skip silently propagates to the subclass" do
    # LegacySubController never asked to be ungated, but inherits the
    # skip_before_action only: [:dashboard] from LegacyController — so
    # legacy_sub#dashboard (a DIFFERENT permission key nobody granted) is open
    # to any signed-in user.
    login_as @roleless
    get "/legacy_sub/dashboard"
    assert_response :success

    get "/legacy_sub/stats"
    assert_response :forbidden
  end
end
