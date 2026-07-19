require "test_helper"

# Originally the pre-gem baseline ("any signed-in user can hit everything").
# After the retrofit it documents the delta + probe 8 (unrouted action).
class LegacyPreGemTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Legacy Larry", email: "larry@example.com")
  end

  test "pre-gem behavior is gone: signed-in no longer suffices" do
    login_as @user
    get "/legacy/stats"
    assert_response :forbidden
  end

  test "probe 8: unrouted action is absent from catalog and unreachable" do
    refute CurrentScope.catalog.include?("legacy#secret_unrouted")
    login_as @user
    get "/legacy/secret_unrouted"
    assert_response :not_found # RoutingError is :rescuable in test env
  end
end
