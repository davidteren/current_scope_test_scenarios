require "test_helper"

# Probe 4: grant a role 5 of the 27 god-controller actions via the model API;
# enforcement must be exact per-action.
class PartialGrantTest < ActionDispatch::IntegrationTest
  GRANTED = %w[legacy#stats legacy#export_csv legacy#search legacy#settings legacy#import].freeze

  setup do
    @clerk = User.create!(name: "Clerk Cleo", email: "cleo@example.com")
    CurrentScope.seed_defaults!
    role = CurrentScope::Role.create!(name: "LegacyClerk")
    role.permission_keys = GRANTED
    role.save!
    grant_role!(@clerk, role: role)
    login_as @clerk
  end

  test "the 5 granted actions are allowed" do
    get "/legacy/stats";       assert_response :success
    get "/legacy/export_csv";  assert_response :success
    get "/legacy/search?q=a";  assert_response :success
    get "/legacy/settings";    assert_response :success
    post "/legacy/import";     assert_response :redirect
  end

  test "the other 22 are denied" do
    %w[users_report orders_report export_pdf export_xml advanced_search].each do |a|
      get "/legacy/#{a}"
      assert_response :forbidden, "expected legacy##{a} to be denied"
    end
    %w[import_preview bulk_update bulk_delete approve_all deny_all update_settings
       email_report merge_records archive_old purge].each do |a|
      post "/legacy/#{a}"
      assert_response :forbidden, "expected legacy##{a} to be denied"
    end
  end

  # 0.3.0 (#20): F8 fixed — unknown keys now make the role invalid instead of
  # vanishing silently; assign_permission_keys(..., scrub: true) is the
  # deliberate drop-stale-keys path and reports what it rejected.
  test "permission_keys= rejects keys not in the catalog loudly" do
    role = CurrentScope::Role.create!(name: "TypoRole")
    role.permission_keys = [ "legacy#stats", "legacy#does_not_exist", "legacy#secret_unrouted" ]
    error = assert_raises(ActiveRecord::RecordInvalid) { role.save! }
    assert_match "legacy#does_not_exist", error.message

    role.assign_permission_keys([ "legacy#stats", "legacy#does_not_exist", "legacy#secret_unrouted" ], scrub: true)
    role.save!
    assert_equal [ "legacy#stats" ], role.reload.permission_keys
    assert_equal [ "legacy#does_not_exist", "legacy#secret_unrouted" ], role.permission_keys_change[:rejected]
  end
end
