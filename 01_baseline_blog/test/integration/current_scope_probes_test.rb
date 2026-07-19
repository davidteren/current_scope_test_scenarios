require "test_helper"

# Probes for the current_scope engine (scenario 01: baseline blog quickstart).
# Assertions pin OBSERVED behavior; surprises are recorded in FINDINGS.md.
class CurrentScopeProbesTest < ActionDispatch::IntegrationTest
  setup do
    CurrentScope.seed_defaults!
    @owner_role  = CurrentScope::Role.find_by!(name: "Owner")
    @member_role = CurrentScope::Role.find_by!(name: "Member")

    @owner  = User.create!(name: "Olivia Owner", email: "owner@t.example")
    @member = User.create!(name: "Marty Member", email: "member@t.example")
    @nobody = User.create!(name: "Nadia NoRole", email: "nobody@t.example")

    grant_role!(@owner, role: @owner_role)

    @post1 = Post.create!(title: "Scoped-visible post", body: "alpha")
    @post2 = Post.create!(title: "Hidden post", body: "beta")
  end

  # ---- Probe 2: fail-closed -------------------------------------------------

  test "signed-OUT user hitting posts#index gets 403 with reason header and empty body" do
    get posts_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_equal "", response.body.strip, "expected head :forbidden (no error page body)"
  end

  test "signed-in user with NO role gets 403 no_grant, not a 500" do
    login_as @nobody
    get posts_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_equal "", response.body.strip
  end

  # ---- Probe 3: Member seed role defaults ------------------------------------

  test "Member seed role grants NOTHING by default - member is still 403 everywhere" do
    assert_equal [], @member_role.role_permissions.pluck(:permission_key),
      "documenting: seed Member role ships with an empty permission set"
    refute @member_role.full_access

    grant_role!(@member, role: @member_role)
    login_as @member
    get posts_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "Member becomes useful only after ticking permissions" do
    @member_role.role_permissions.create!(permission_key: "posts#index")
    grant_role!(@member, role: @member_role)
    login_as @member

    get posts_path
    assert_response :success

    get new_post_path
    assert_response :forbidden, "posts#new not granted"
  end

  # ---- Probe 4: Owner everywhere; management UI gate --------------------------

  test "owner (full_access) can use every posts action and the management UI" do
    login_as @owner

    get posts_path
    assert_response :success

    get new_post_path
    assert_response :success

    post posts_path, params: { post: { title: "By owner", body: "x" } }
    assert_response :redirect

    get current_scope_path
    assert_response :success

    get current_scope.roles_path
    assert_response :success
  end

  test "non-full-access users get 403 from the management UI" do
    grant_role!(@member, role: @member_role)
    login_as @member
    get current_scope_path
    assert_response :forbidden

    delete logout_path
    login_as @nobody
    get current_scope_path
    assert_response :forbidden

    delete logout_path # signed out entirely
    get current_scope_path
    assert_response :forbidden
  end

  # ---- Probe 5: scope_for + allowed_to? agreement ------------------------------

  test "scope_for: owner sees all, scoped grant sees exactly one, no grant sees none" do
    viewer_role = CurrentScope::Role.create!(name: "Viewer")
    viewer_role.role_permissions.create!(permission_key: "posts#index")
    viewer_role.role_permissions.create!(permission_key: "posts#show")
    grant_scoped_role!(@member, role: viewer_role, record: @post1)

    # Owner: index lists every post.
    login_as @owner
    get posts_path
    assert_response :success
    assert_includes response.body, @post1.title
    assert_includes response.body, @post2.title
    delete logout_path

    # Scoped viewer: hmm - can they even reach posts#index? Scoped grant is
    # per-record; the INDEX gate has no record. Observe.
    login_as @member
    get posts_path
    # OBSERVED: still 403 - PostsController declares current_scope_record (nil on
    # index) but no current_scope_model, so the record-less gate stays closed.
    assert_response :forbidden,
      "scoped-only grant does not open the collection action without current_scope_model"
    # 0.3.0 (#50): the denial now names the gap - the reason is model_undeclared
    # (was no_grant) because the subject's scoped grant ticks the key and the
    # controller declared the record hook but not the type.
    assert_equal "model_undeclared", response.headers["X-Current-Scope-Reason"]

    # But show on the granted record works, and not on the other.
    get post_path(@post1)
    assert_response :success
    get post_path(@post2)
    assert_response :forbidden
  end

  test "scope_for and allowed_to? agree per record (unit-level, via with_current_user)" do
    viewer_role = CurrentScope::Role.create!(name: "Viewer2")
    viewer_role.role_permissions.create!(permission_key: "posts#index")
    grant_scoped_role!(@member, role: viewer_role, record: @post1)

    with_current_user(@owner) do
      assert_equal Post.all.to_a.sort_by(&:id),
        CurrentScope.scope_for(subject: @owner, model: Post, permission: "posts#index").to_a.sort_by(&:id)
    end

    with_current_user(@member) do
      scoped = CurrentScope.scope_for(subject: @member, model: Post, permission: "posts#index")
      assert_equal [ @post1 ], scoped.to_a
      assert CurrentScope.allowed?("posts#index", subject: @member, record: @post1)
      refute CurrentScope.allowed?("posts#index", subject: @member, record: @post2)
    end

    with_current_user(@nobody) do
      assert_empty CurrentScope.scope_for(subject: @nobody, model: Post, permission: "posts#index").to_a
    end

    # nil subject: fail closed
    assert_empty CurrentScope.scope_for(subject: nil, model: Post, permission: "posts#index").to_a
  end

  # ---- Probe 6: view helpers in ERB + partial ---------------------------------

  test "allowed_to? hides Edit/Destroy for a read-only role, shows them for owner" do
    reader = CurrentScope::Role.create!(name: "Reader")
    %w[posts#index posts#show].each { |k| reader.role_permissions.create!(permission_key: k) }
    grant_role!(@member, role: reader)

    login_as @member
    get post_path(@post1)
    assert_response :success
    refute_includes response.body, "Edit this post"
    refute_includes response.body, "Destroy this post"
    refute_includes response.body, "Edit (partial)", "allowed_to? inside the partial"
    delete logout_path

    login_as @owner
    get post_path(@post1)
    assert_response :success
    assert_includes response.body, "Edit this post"
    assert_includes response.body, "Destroy this post"
    assert_includes response.body, "Edit (partial)"
  end

  # ---- Probe 5 (the trap): the advertised scoped-index story is unreachable ---

  # 0.3.0 (#50/#65) ships the real fix — declare current_scope_model alongside the
  # record hook (see the FIX test below) — but the org-grant escape hatch pinned
  # here behaves exactly as it did in 0.2.0.
  test "TRAP: a scoped-only user cannot use the index; adding the org grant needed to reach it shows ALL records" do
    viewer_role = CurrentScope::Role.create!(name: "Viewer3")
    viewer_role.role_permissions.create!(permission_key: "posts#index")
    grant_scoped_role!(@member, role: viewer_role, record: @post1)

    # Without an org-wide posts#index the gate 403s (asserted in the other
    # test). Give the org-wide grant the gate demands:
    org_reader = CurrentScope::Role.create!(name: "OrgReader")
    org_reader.role_permissions.create!(permission_key: "posts#index")
    grant_role!(@member, role: org_reader)

    login_as @member
    get posts_path
    assert_response :success
    # scope_for(Post) resolves the SAME key the org role now grants, so the
    # scoped filter is moot: the user sees EVERY post, not just their granted one.
    assert_includes response.body, @post1.title
    assert_includes response.body, @post2.title,
      "documenting: org grant needed to pass the gate also makes scope_for return ALL"
  end

  test "workaround: scope_for keyed to a DIFFERENT permission (show) yields the scoped subset" do
    viewer_role = CurrentScope::Role.create!(name: "Viewer4")
    viewer_role.role_permissions.create!(permission_key: "posts#show")
    grant_scoped_role!(@member, role: viewer_role, record: @post1)

    org_reader = CurrentScope::Role.create!(name: "OrgReader2")
    org_reader.role_permissions.create!(permission_key: "posts#index")
    grant_role!(@member, role: org_reader)

    with_current_user(@member) do
      subset = CurrentScope.scope_for(subject: @member, model: Post, permission: "posts#show")
      assert_equal [ @post1 ], subset.to_a
    end
  end

  # 0.3.0 (#50/#65): the trap's FIX. CommentsController now declares BOTH hooks
  # (current_scope_record, nil on collection actions, plus current_scope_model =
  # Comment), so a scoped-only subject opens the index and scope_for narrows it.
  test "FIX (0.3.0): declaring record+model hooks opens the scoped subject's index, narrowed to their records" do
    granted = Comment.create!(post: @post1, body: "granted-comment-alpha")
    hidden  = Comment.create!(post: @post2, body: "hidden-comment-beta")

    commenter = CurrentScope::Role.create!(name: "Commenter")
    %w[comments#index comments#show].each { |k| commenter.role_permissions.create!(permission_key: k) }
    grant_scoped_role!(@member, role: commenter, record: granted)

    login_as @member
    get comments_path
    assert_response :success,
      "scoped-only subject passes the collection-read gate once both hooks are declared"
    assert_includes response.body, "granted-comment-alpha"
    refute_includes response.body, "hidden-comment-beta",
      "scope_for narrows the index to the granted record"

    # Member actions unchanged: show works only on the granted record.
    get comment_path(granted)
    assert_response :success
    get comment_path(hidden)
    assert_response :forbidden
  end

  # ---- Probe 10: host-side nice 403 page --------------------------------------

  test "a host rescue_from AccessDenied in a subclass controller beats the gem's bare head :forbidden" do
    login_as @nobody
    get comments_path
    assert_response :forbidden
    assert_includes response.body, "Sorry, you do not have permission (no_grant)."
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  # ---- Probe 9 (test-env half): new controller is fail-closed from birth ------

  test "about#show (added after initial build) is fail-closed for everyone but owner" do
    get about_path
    assert_response :forbidden

    login_as @owner
    get about_path
    assert_response :success
  end

  # ---- Probe 8: audit events -------------------------------------------------

  test "grants made via seeds/test-helpers/grant! record NO audit events" do
    assert_equal 0, CurrentScope::Event.count,
      "documenting: seed_defaults! + grant_role! in setup recorded nothing"

    CurrentScope.grant!(@nobody)
    assert_equal 0, CurrentScope::Event.count,
      "documenting: CurrentScope.grant! (the documented bootstrap path) records no audit event"
  end

  test "grants made through the management UI DO record audit events" do
    login_as @owner
    role = CurrentScope::Role.create!(name: "Auditable")

    # 0.3.0 (#85): `resource :role_assignment` became `resources :role_assignments`,
    # so the create helper is plural now.
    post current_scope.role_assignments_path,
      params: { subject_gid: @nobody.to_gid.to_s, role_id: role.id }
    assert_response :redirect

    events = CurrentScope::Event.all.to_a
    assert_equal 1, events.size
    assert_equal "org_role.assigned", events.first.event
    assert_equal @nobody.to_gid.to_s, events.first.target
  end

  # ---- Probe 2 extra: what the denial looks like for HTML users ---------------

  test "denied HTML request has no error page, content-type or redirect - bare 403" do
    login_as @nobody
    get posts_path
    assert_response :forbidden
    assert_nil response.headers["Location"]
    assert_equal "", response.body.strip
  end
end
