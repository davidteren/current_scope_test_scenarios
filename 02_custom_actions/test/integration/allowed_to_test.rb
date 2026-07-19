require "test_helper"

# Probe 5: allowed_to?(:approve, report) short form — inside the resource's own
# controller and cross-resource from another controller's view.
class AllowedToTest < ActiveSupport::TestCase
  # Simulates being inside ReportsController / a reports view.
  class InsideReports
    include CurrentScope::Permissions
    def controller_path = "reports"
  end

  # Simulates a view rendered by WizardController (cross-resource check).
  class InsideWizard
    include CurrentScope::Permissions
    def controller_path = "wizard"
  end

  setup { seed_roles! }

  test "short form resolves to reports#approve inside ReportsController" do
    grant_role!(users(:dave), role: make_role!("Approver", %w[reports#approve]))
    with_current_user(users(:dave)) do
      ctx = InsideReports.new
      assert ctx.allowed_to?(:approve, reports(:q2))
      assert_not ctx.allowed_to?(:reject, reports(:q2))
      assert_not ctx.allowed_to?(:update, reports(:q2))
    end
  end

  test "cross-resource: from a wizard view the record's route key wins" do
    grant_role!(users(:dave), role: make_role!("Approver2", %w[reports#approve]))
    with_current_user(users(:dave)) do
      ctx = InsideWizard.new
      # record present -> reports#approve (route key), NOT wizard#approve
      assert ctx.allowed_to?(:approve, reports(:q2))
    end
  end

  test "bare action with no record inside wizard resolves to wizard#<action>" do
    grant_role!(users(:dave), role: make_role!("StepOne", %w[wizard#step_one]))
    with_current_user(users(:dave)) do
      ctx = InsideWizard.new
      assert ctx.allowed_to?(:step_one)
      assert_not ctx.allowed_to?(:complete)
    end
  end

  test "explicit full key works from anywhere" do
    grant_role!(users(:dave), role: make_role!("Approver3", %w[reports#approve]))
    with_current_user(users(:dave)) do
      assert Object.new.extend(CurrentScope::Permissions).allowed_to?("reports#approve")
    end
  end
end

# View-level check through a real request: buttons rendered off allowed_to?.
class AllowedToViewTest < ActionDispatch::IntegrationTest
  setup { seed_roles! }

  test "show page renders only the buttons the subject may use" do
    grant_role!(users(:dave), role: make_role!("ShowApprove", %w[reports#show reports#approve]))
    sign_in users(:dave)

    get report_path(reports(:q2))
    assert_response :success
    assert_includes response.body, approve_report_path(reports(:q2))
    assert_not_includes response.body, publish_report_path(reports(:q2))
    assert_not_includes response.body, clone_report_path(reports(:q2))
  end
end
