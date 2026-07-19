require "test_helper"

# Probe 4 + 8: routing edge cases, catalog sanity, odd verbs.
class RoutingEdgesTest < ActionDispatch::IntegrationTest
  setup { create_users_and_roles! }

  test "(a) rack proc route is skipped by the catalog and serves untouched" do
    assert_not CurrentScope.catalog.keys.any? { |k| k.include?("ping") }
    get "/ping"
    assert_response :success
    assert_equal "pong", response.body
  end

  test "(b) phantom permission: route to a nonexistent controller IS in the catalog and grantable" do
    assert CurrentScope.catalog.include?("ghosts#index")

    role = CurrentScope::Role.create!(name: "Ghostly")
    role.permission_keys = [ "ghosts#index" ]
    role.save!
    assert role.grants?("ghosts#index"), "phantom key survives the catalog filter and persists"

    # Hitting the phantom route raises ActionDispatch::MissingController —
    # NOT a rescuable RoutingError, so in production this is a 500, not a 404.
    error = assert_raises(ActionDispatch::MissingController) { get "/ghosts" }
    assert_match(/uninitialized constant GhostsController/, error.message)
  end

  test "(c) constrained route is gated normally when matched, 404 when not" do
    post "/sessions", params: { user_id: @owner.id }
    get "/beta_items", params: { beta: "1" }
    assert_response :success

    get "/beta_items"
    assert_response :not_found
  end

  test "(c) scoped module route lands in the catalog under its module path" do
    assert CurrentScope.catalog.include?("api/health#health")
  end

  test "(c) redirect route is skipped by the catalog and redirects" do
    assert_not CurrentScope.catalog.keys.any? { |k| k.include?("old") }
    get "/old"
    assert_response :moved_permanently
    assert_equal "http://www.example.com/new", response.headers["Location"]
  end

  test "(d) two paths to the same controller#action dedupe to one permission" do
    assert_equal 1, CurrentScope.catalog.keys.count("items#index")

    post "/sessions", params: { user_id: @owner.id }
    get "/items_alias"
    assert_response :success
  end

  test "(e) engine's own routes are excluded from the catalog" do
    assert_empty CurrentScope.catalog.keys.grep(%r{\Acurrent_scope/})
    assert_empty CurrentScope.catalog.keys.grep(%r{\Arails/})
  end

  # --- Probe 8: odd verbs ---------------------------------------------------

  test "HEAD passes the mutation guard and hits the permission gate" do
    head "/api/v1/items", headers: bearer(@owner)
    assert_response :success

    head "/api/v1/items"
    assert_response :forbidden
  end

  test "OPTIONS with no route 404s before any gate" do
    options "/api/v1/items"
    assert_response :not_found
  end

  test "OPTIONS routed to a gated action is treated like any request" do
    post "/sessions", params: { user_id: @owner.id }
    options "/cors_probe"
    assert_response :success

    delete "/logout"
    options "/cors_probe"
    assert_response :forbidden
  end

  test "wrong verb on a member action 404s before the gate" do
    put "/api/v1/items/#{@anvil.id}/publish", headers: bearer(@owner)
    assert_response :not_found
  end
end
