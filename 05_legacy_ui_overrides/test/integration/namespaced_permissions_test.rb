require "test_helper"

# Probe 1: reports#index vs admin/reports#index are independent permissions.
# Probe 3: allowed_to?(:approve, report) resolution inside admin/reports vs
# from a top-level reports view (uncataloged reports#approve).
class NamespacedPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    seed_roles!
  end

  test "top-level grant does not open the admin namespace" do
    role = create_role!("TopOnly", %w[reports#index reports#show])
    grant_role!(users(:ada), role: role) # ada IS host-admin, but lacks the grant
    sign_in_as users(:ada)

    get reports_path
    assert_response :success

    get admin_reports_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_includes response.body, "admin/reports#index" # branded page names the key
  end

  test "admin namespace grant does not open the top-level controller" do
    role = create_role!("AdminOnly", %w[admin/reports#index admin/reports#show])
    grant_role!(users(:ada), role: role)
    sign_in_as users(:ada)

    get admin_reports_path
    assert_response :success

    get reports_path
    assert_response :forbidden
    assert_includes response.body, "reports#index"
  end

  test "inside admin/reports the short-form approve check resolves to admin/reports#approve" do
    role = create_role!("Approver", %w[admin/reports#index admin/reports#approve])
    grant_role!(users(:ada), role: role)
    sign_in_as users(:ada)

    get admin_reports_path
    assert_response :success
    assert_includes response.body, "approve-btn-#{reports(:q1).id}"

    post approve_admin_report_path(reports(:q1))
    assert_response :redirect
    assert_equal "approved", reports(:q1).reload.state
  end

  test "without the approve grant the admin approve button hides and the action 403s" do
    role = create_role!("AdminViewer", %w[admin/reports#index admin/reports#show])
    grant_role!(users(:ada), role: role)
    sign_in_as users(:ada)

    get admin_reports_path
    assert_response :success
    refute_includes response.body, "approve-btn-"

    post approve_admin_report_path(reports(:q1))
    assert_response :forbidden
  end

  test "top-level :approve check derives uncataloged reports#approve and is silently false" do
    # ada holds admin/reports#approve, but from a reports view the short form
    # derives reports#approve — an unrouted, ungrantable key.
    role = create_role!("Approver2", %w[reports#index admin/reports#approve])
    grant_role!(users(:ada), role: role)
    sign_in_as users(:ada)

    get reports_path
    assert_response :success
    refute_includes response.body, "approve-visible-from-reports",
      "allowed_to?(:approve, report) from a top-level reports view should be false"
  end

  test "a grant row for an uncataloged key makes allowed_to? return true for an unenforceable permission" do
    role = create_role!("Approver3", %w[reports#index])
    # Role#permission_keys= silently DROPS uncataloged keys, so go behind it:
    CurrentScope::RolePermission.create!(role_id: role.id, permission_key: "reports#approve")
    grant_role!(users(:sam), role: role)
    sign_in_as users(:sam)

    get reports_path
    assert_response :success
    assert_includes response.body, "approve-visible-from-reports",
      "resolver consults grant rows without validating the key against the catalog"
  end

  test "permission_keys= rejects uncataloged keys loudly; scrub: true opts back into dropping" do
    # 0.3.0 (#20): unknown keys now fail validation instead of silently dropping (was FINDINGS F7).
    role = CurrentScope::Role.create!(name: "TypoRole")
    error = assert_raises(ActiveRecord::RecordInvalid) do
      role.update!(permission_keys: %w[report#show reports#approve reports#index])
    end
    assert_match(/report#show, reports#approve/, error.message,
      "the error names the offending keys")

    role.assign_permission_keys(%w[report#show reports#approve reports#index], scrub: true)
    role.save!
    assert_equal %w[reports#index], role.reload.permission_keys,
      "scrub: true is the deliberate opt-in to the old dropping behavior"
  end
end
