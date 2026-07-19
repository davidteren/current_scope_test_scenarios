require "test_helper"

# Probe 9: SoD on a custom action (config.sod_actions = %w[approve],
# Report#current_scope_initiator = requested_by).
class SodTest < ActionDispatch::IntegrationTest
  setup { seed_roles! }

  test "full-access initiator is vetoed on their own report" do
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)

    post approve_report_path(reports(:q1))   # alice requested q1
    assert_response :forbidden
    assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
    assert_equal "draft", reports(:q1).reload.state
  end

  test "full-access non-initiator may approve" do
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)

    post approve_report_path(reports(:q2))   # bob's report
    assert_redirected_to report_path(reports(:q2))
    assert_equal "approved", reports(:q2).reload.state
  end

  test "org-granted approver: allowed on others, vetoed on own" do
    grant_role!(users(:bob), role: make_role!("Approver", %w[reports#approve]))
    sign_in users(:bob)

    post approve_report_path(reports(:q1))   # alice's report
    assert_redirected_to report_path(reports(:q1))

    post approve_report_path(reports(:q2))   # bob's own report
    assert_response :forbidden
    assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
  end

  test "advisory allowed_to? agrees with the gate on SoD" do
    with_current_user(users(:alice)) do
      grant_role!(users(:alice), role: @owner_role)
      helper = Object.new.extend(CurrentScope::Permissions)
      assert_not helper.allowed_to?(:approve, reports(:q1)), "initiator should see approve as denied"
      assert helper.allowed_to?(:approve, reports(:q2))
    end
  end
end
