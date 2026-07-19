require "test_helper"

# Probe 9: excluding a controller from the grid while it still includes Guard
# must raise a loud ConfigurationError pointing at the fix.
class ExcludedControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(name: "Excl Ed", email: "ed@example.com")
    make_owner!(@owner)
    @original = CurrentScope.config.excluded_controllers.dup
  end

  teardown do
    CurrentScope.config.excluded_controllers = @original
    CurrentScope.reset_catalog!
  end

  test "gating an excluded controller raises ConfigurationError with actionable message" do
    CurrentScope.config.excluded_controllers += [ %r{\Alegacy\z} ]
    CurrentScope.reset_catalog!
    login_as @owner

    err = assert_raises(CurrentScope::ConfigurationError) { get "/legacy/stats" }
    assert_match "legacy#stats", err.message
    assert_match "excluded_controllers", err.message
    assert_match "skip_before_action :current_scope_check!", err.message
  end

  test "the excluded regex removes only legacy, not legacy_sub" do
    CurrentScope.config.excluded_controllers += [ %r{\Alegacy\z} ]
    CurrentScope.reset_catalog!
    keys = CurrentScope.catalog.keys
    refute keys.any? { |k| k.start_with?("legacy#") }
    assert keys.any? { |k| k.start_with?("legacy_sub#") }
  end
end
