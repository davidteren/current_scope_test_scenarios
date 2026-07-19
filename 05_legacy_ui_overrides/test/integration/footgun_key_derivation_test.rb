require "test_helper"

# Probe 2: the documented key-derivation foot-gun (controller path segment !=
# record route key) and its prescribed fix.
# Probe 9: the branded host 403 page from rescue_from CurrentScope::AccessDenied.
class FootgunKeyDerivationTest < ActionDispatch::IntegrationTest
  setup do
    seed_roles!
  end

  test "link shows but 403s: reports-granted user sees the dashboard link, click gets 403" do
    role = create_role!("ReportsOnly", %w[reports#index reports#show])
    grant_role!(users(:sam), role: role)
    sign_in_as users(:sam)

    get reports_path
    assert_response :success
    # The foot-gun guard (allowed_to?(:show, report) → reports#show) shows the link…
    assert_includes response.body, "dashboard-link-footgun"
    # …while the correct guard (explicit "dashboard#show") hides it.
    refute_includes response.body, "dashboard-link-fixed"

    # Clicking through: the gate enforces dashboard#show → 403, exactly as the README warns.
    get dashboard_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "hide that would work: dashboard-only user loses the short-form widget on the page they are viewing" do
    role = create_role!("DashboardOnly", %w[dashboard#show])
    grant_role!(users(:sam), role: role)
    sign_in_as users(:sam)

    get dashboard_path
    assert_response :success
    # Explicit full key agrees with the gate that just passed:
    assert_includes response.body, "widget-fullkey"
    # Short form derives reports#show and disagrees with the gate — display bug per README:
    refute_includes response.body, "widget-shortform"
  end

  test "guard stays authoritative: the mismatch is a display bug, not a bypass" do
    role = create_role!("ReportsOnly2", %w[reports#index reports#show])
    grant_role!(users(:sam), role: role)

    with_current_user(users(:sam)) do
      # What the reports view checks (derives reports#show): true.
      assert CurrentScope.allowed?(:show, subject: users(:sam), record: reports(:q1), controller_path: "reports")
      # What the dashboard gate checks: false.
      refute CurrentScope.allowed?("dashboard#show", subject: users(:sam))
    end
  end

  test "branded 403 page renders with permission key, reason and host design" do
    role = create_role!("NothingMuch", %w[reports#index])
    grant_role!(users(:sam), role: role)
    sign_in_as users(:sam)

    get dashboard_path
    assert_response :forbidden
    assert_includes response.body, "branded-403"
    assert_includes response.body, "dashboard#show"      # AccessDenied#message
    assert_includes response.body, "no_grant"            # AccessDenied#reason
    assert_includes response.body, "bootstrap"           # host layout in use
  end

  test "signed-out user is denied fail-closed with no_grant" do
    get dashboard_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end
end
