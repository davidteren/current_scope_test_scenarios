require "test_helper"

# Probe 1 + 2 + 6 + 7: Context/Guard on ActionController::API, denial
# rendering for JSON, scope_for correctness, content negotiation.
class ApiGuardTest < ActionDispatch::IntegrationTest
  setup { create_users_and_roles! }

  # --- Probe 1: Context + Guard on ActionController::API -------------------

  test "token-authed owner passes the gate on an API controller" do
    get "/api/v1/items", headers: bearer(@owner)
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  test "member org-wide grant works on API index but not show" do
    get "/api/v1/items", headers: bearer(@member)
    assert_response :success

    get "/api/v1/items/#{@anvil.id}", headers: bearer(@member)
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "no token is fail-closed denied" do
    get "/api/v1/items"
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  # --- Probe 2: out-of-box denial rendering (no custom rescue) -------------

  test "OUT-OF-BOX denial on ActionController::API: capture status, body, content type" do
    get "/api/raw"
    # MutationGuard installs rescue_from AccessDenied -> head :forbidden,
    # so the out-of-box result is a 403 with an EMPTY body (not a 500).
    assert_response :forbidden
    assert_equal "", response.body
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "custom rescue_from gives a JSON error body (the API pattern)" do
    get "/api/v1/items/#{@anvil.id}", headers: bearer(@nobody)
    assert_response :forbidden
    assert_equal({ "error" => "forbidden", "reason" => "no_grant" }, JSON.parse(response.body))
  end

  # --- Probe 6: scope_for on the API index with scoped grants --------------

  # FINDING (major): the gate and scope_for disagree for scoped-only subjects.
  # scope_for(Item) correctly returns [bucket], allowed_to?(:index, bucket) is
  # true, but the GATE on the index action sees record=nil, so scoped grants
  # are invisible and the subject 403s at the door of the very list that would
  # show their records. The README index recipe is unreachable for them.
  # 0.3.0 (#50/#65): fixable now — declaring current_scope_model on the
  # controller opens the record-less gate via scope_for; without the model
  # hook the denial reason names the fix (model_undeclared) instead of no_grant.
  test "scoped-only subject is DENIED the index action even though scope_for would list records" do
    viewer = CurrentScope::Role.create!(name: "Viewer")
    viewer.role_permissions.create!(permission_key: "api/v1/items#index")
    viewer.role_permissions.create!(permission_key: "api/v1/items#show")
    grant_scoped_role!(@nobody, role: viewer, record: @bucket)

    # The list-side answer exists...
    scoped = CurrentScope.resolver.scope_for(subject: @nobody, model: Item, permission: "api/v1/items#index")
    assert_equal [ @bucket.id ], scoped.pluck(:id)
    # ...and the per-record check passes...
    assert CurrentScope.resolver.allow?(subject: @nobody, permission: "api/v1/items#index", record: @bucket)
    # ...but the gated index action is a 403 (record hook returns nil and no
    # current_scope_model is declared, so the gate can't bind the type).
    get "/api/v1/items", headers: bearer(@nobody)
    assert_response :forbidden
    # 0.3.0 (#50): reason is model_undeclared now (was no_grant) — the subject
    # holds a scoped grant ticking the key, so the gate names the missing hook.
    assert_equal "model_undeclared", response.headers["X-Current-Scope-Reason"]

    # Member actions behave correctly under the scoped grant:
    get "/api/v1/items/#{@bucket.id}", headers: bearer(@nobody)
    assert_response :success

    get "/api/v1/items/#{@anvil.id}", headers: bearer(@nobody)
    assert_response :forbidden
  end

  # And the flip side: an org-wide grant of index makes scope_for return ALL
  # records — so no grant combination yields a gated index that lists only the
  # scoped subset when keyed on the default index permission.
  test "org-wide index grant means scope_for lists every record" do
    get "/api/v1/items", headers: bearer(@member)
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  test "mutations: owner may create, publish, destroy; ungranted may not" do
    post "/api/v1/items", params: { item: { name: "Drum" } }, as: :json, headers: bearer(@owner)
    assert_response :created

    post "/api/v1/items/#{@anvil.id}/publish", headers: bearer(@owner)
    assert_response :success
    assert JSON.parse(response.body)["published"]

    delete "/api/v1/items/#{@anvil.id}", headers: bearer(@owner)
    assert_response :no_content

    post "/api/v1/items", params: { item: { name: "Echo" } }, as: :json, headers: bearer(@nobody)
    assert_response :forbidden
  end

  # --- Probe 7: content negotiation -----------------------------------------

  test "denial rendering is format-blind out of the box: HTML gets the same bare 403" do
    post "/sessions", params: { user_id: @nobody.id }
    get "/items"
    assert_response :forbidden
    assert_equal "", response.body # blank page for a browser
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "hybrid apps need BOTH keys granted: items#index does not imply api/v1/items#index" do
    solo = CurrentScope::Role.create!(name: "HtmlOnly")
    solo.role_permissions.create!(permission_key: "items#index")
    grant_role!(@nobody, role: solo)

    post "/sessions", params: { user_id: @nobody.id }
    get "/items"
    assert_response :success

    get "/api/v1/items", headers: bearer(@nobody)
    assert_response :forbidden
  end

  # --- Probe 8 adjacent: 403 vs 404 existence oracle ------------------------

  test "existing id yields 403, missing id yields 404 - an enumeration oracle for anonymous callers" do
    get "/api/v1/items/#{@anvil.id}"
    assert_response :forbidden

    get "/api/v1/items/999999"
    assert_response :not_found
  end
end
