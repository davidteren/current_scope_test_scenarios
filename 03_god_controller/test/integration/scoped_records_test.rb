require "test_helper"

# Probe 5: :id-routed actions + scoped roles + the single multi-model
# current_scope_record hook.
class ScopedRecordsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Scopey Sam", email: "sam@example.com")
    @acme   = Customer.create!(name: "Acme", active: true)
    @globex = Customer.create!(name: "Globex", active: true)
    @widget = Widget.create!(name: "Sprocket")
    @order  = Order.create!(number: "O-9", status: "ok", archived: true)
    CurrentScope.seed_defaults!
    login_as @user
  end

  def role_granting(*keys)
    role = CurrentScope::Role.create!(name: "r-#{keys.hash.abs}")
    role.permission_keys = keys
    role.save!
    role
  end

  test "scoped grant on THIS customer unlocks toggle_active on it only" do
    role = role_granting("legacy#toggle_active")
    grant_scoped_role!(@user, role: role, record: @acme)

    post "/legacy/#{@acme.id}/toggle_active"
    assert_response :redirect

    post "/legacy/#{@globex.id}/toggle_active"
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "one hook dispatches to different models per action (Widget + Order)" do
    wrole = role_granting("legacy#print_view")
    orole = role_granting("legacy#restore")
    grant_scoped_role!(@user, role: wrole, record: @widget)
    grant_scoped_role!(@user, role: orole, record: @order)

    get "/legacy/#{@widget.id}/print_view"
    assert_response :success

    post "/legacy/#{@order.id}/restore"
    assert_response :success
    assert_equal false, @order.reload.archived
  end

  test "an :id action NOT covered by the hook can never be unlocked by a scoped role (fail closed)" do
    role = role_granting("legacy#assign")
    grant_scoped_role!(@user, role: role, record: @acme)

    post "/legacy/#{@acme.id}/assign"
    assert_response :forbidden # hook returns nil for assign -> scoped grant inert
    # 0.3.0 (#50): the silently-inert scoped grant (F6) now has a name — the
    # deny reason is model_undeclared (record hook nil, no current_scope_model
    # declared, subject holds a scoped grant ticking this key).
    assert_equal "model_undeclared", response.headers["X-Current-Scope-Reason"]

    # 0.3.0: model_undeclared hard-403s even under enforcement = :report —
    # report mode downgrades ONLY :no_grant, so a retrofit team's report-mode
    # traffic surfaces this misconfiguration as a real 403, not a pass-through.
    CurrentScope.config.enforcement = :report
    post "/legacy/#{@acme.id}/assign"
    assert_response :forbidden
    assert_equal "model_undeclared", response.headers["X-Current-Scope-Reason"]
  ensure
    CurrentScope.config.enforcement = :enforce
  end

  test "org-wide grant unlocks an uncovered :id action regardless" do
    role = role_granting("legacy#assign")
    grant_role!(@user, role: role)

    post "/legacy/#{@acme.id}/assign"
    assert_response :redirect
  end

  test "cross-model id confusion: a scoped Customer grant is checked against the WRONG model when ids collide" do
    # toggle_active loads Customer; restore loads Order. Ids are separate
    # sequences, so Customer #1 and Order #1 both exist. The hook is the only
    # thing keeping them apart — the permission key alone does not encode the
    # model. Verify a Customer-scoped grant can't unlock restore on the Order
    # with the same numeric id.
    order = Order.find_or_create_by!(number: "collide") { |o| o.status = "x"; o.archived = true }
    role = role_granting("legacy#restore")
    grant_scoped_role!(@user, role: role, record: @acme) # Customer-scoped

    post "/legacy/#{order.id}/restore"
    assert_response :forbidden
  end

  test "SECURITY-ADJACENT: existence oracle — an unauthorized user can distinguish real ids (403) from fake ids (404)" do
    # No grants at all. The record hook loads BEFORE the deny decision, so
    # RecordNotFound (404) fires for fake ids while real ids reach the
    # resolver and 403 — response code leaks whether a Customer id exists.
    post "/legacy/#{@acme.id}/toggle_active"
    assert_response :forbidden

    post "/legacy/999999/toggle_active"
    assert_response :not_found
  end

  test "hook raising RecordNotFound surfaces as 404 before authorization" do
    role = role_granting("legacy#toggle_active")
    grant_role!(@user, role: role)

    post "/legacy/999999/toggle_active"
    assert_response :not_found
  end
end
