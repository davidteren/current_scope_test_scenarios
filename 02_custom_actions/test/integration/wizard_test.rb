require "test_helper"

# Probe 7: non-resourceful controller (plain get/post routes, no model).
class WizardTest < ActionDispatch::IntegrationTest
  setup { seed_roles! }

  test "wizard actions are gated and individually grantable" do
    grant_role!(users(:dave), role: make_role!("StepOneOnly", %w[wizard#step_one]))
    sign_in users(:dave)

    get "/wizard/step_one"
    assert_response :success
    assert_match "wizard step one", response.body

    post "/wizard/submit_step_one", params: { answer: "42" }
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]

    get "/wizard/step_two"
    assert_response :forbidden

    post "/wizard/complete"
    assert_response :forbidden
  end

  test "owner can walk the whole wizard" do
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)

    get "/wizard/step_one"
    assert_response :success
    post "/wizard/submit_step_one", params: { answer: "42" }
    assert_redirected_to "/wizard/step_two"
    follow_redirect!
    assert_match "answer: 42", response.body
    post "/wizard/complete"
    assert_match "wizard complete", response.body
  end

  test "signed-out wizard access is denied" do
    get "/wizard/step_one"
    assert_response :forbidden
  end
end
