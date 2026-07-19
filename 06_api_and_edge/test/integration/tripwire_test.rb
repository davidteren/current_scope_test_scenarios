require "test_helper"

# Probe 3: GatingTripwire on API controllers.
class TripwireTest < ActionDispatch::IntegrationTest
  setup { create_users_and_roles! }

  test "(a) properly gated action does not trip" do
    get "/api/v1/items", headers: bearer(@owner)
    assert_response :success
  end

  test "(b) ungated action on a tripwired base raises after the action" do
    error = assert_raises(CurrentScope::ConfigurationError) { get "/api/boom" }
    assert_match(/api\/health#boom.*completed without running current_scope_check!/m, error.message)
  end

  test "(c) current_scope_skip_tripwire! only: :health lets a public endpoint through" do
    get "/api/health"
    assert_response :success
    assert_equal({ "ok" => true }, JSON.parse(response.body))
  end

  test "(d) documented blind spot: render from a before_action escapes the tripwire" do
    get "/api/halted"
    assert_response :success
    assert_equal({ "leaked_from_before_action" => true }, JSON.parse(response.body))
  end
end
