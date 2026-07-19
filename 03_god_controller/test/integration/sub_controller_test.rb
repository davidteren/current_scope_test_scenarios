require "test_helper"

# Probe 7: LegacySubController < LegacyController — inherited actions under a
# different controller_path are DIFFERENT permissions.
class SubControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Sub Sue", email: "sue@example.com")
    CurrentScope.seed_defaults!
  end

  test "catalog contains the subclass's inherited actions under its own path" do
    keys = CurrentScope.catalog.keys
    assert_includes keys, "legacy_sub#stats"
    assert_includes keys, "legacy_sub#dashboard"
    assert_includes keys, "legacy_sub#only_here"
    # ...and the parent's other 24 actions are NOT duplicated under legacy_sub
    refute_includes keys, "legacy_sub#export_csv"
  end

  test "granting legacy#stats does NOT unlock legacy_sub#stats" do
    role = CurrentScope::Role.create!(name: "ParentOnly")
    role.permission_keys = [ "legacy#stats" ]
    role.save!
    grant_role!(@user, role: role)
    login_as @user

    get "/legacy/stats";     assert_response :success
    get "/legacy_sub/stats"; assert_response :forbidden
  end

  test "granting legacy_sub#stats unlocks the inherited action" do
    role = CurrentScope::Role.create!(name: "SubOnly")
    role.permission_keys = [ "legacy_sub#stats" ]
    role.save!
    grant_role!(@user, role: role)
    login_as @user

    get "/legacy_sub/stats"; assert_response :success
    get "/legacy/stats";     assert_response :forbidden
  end
end
