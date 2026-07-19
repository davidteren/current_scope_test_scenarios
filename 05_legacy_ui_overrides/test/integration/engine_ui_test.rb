require "test_helper"

# Probe 4: engine mounted at /permissions (custom path) — no hardcoded
# /current_scope paths in rendered HTML.
# Probe 5: parent_controller = Admin::BaseController — host auth +
# before_actions gate the engine; engine keeps its own layout.
# Probe 6: subject_label Symbol/Proc forms.
# Probe 8: custom permission_grid_groups collisions.
# Probe 1 (grid half): the two reports rows in the grid.
class EngineUiTest < ActionDispatch::IntegrationTest
  setup do
    seed_roles!
    grant_role!(users(:olive), role: @owner_role) # full access + host admin
  end

  # --- Probe 4 -------------------------------------------------------------

  test "engine works at the custom /permissions mount with no hardcoded /current_scope links" do
    sign_in_as users(:olive)

    %w[/permissions/roles /permissions/subjects /permissions/events].each do |path|
      get path
      assert_response :success, "#{path} should render"
      refute_match %r{(href|action)="/current_scope}, response.body,
        "#{path} contains a hardcoded /current_scope link"
      assert_match %r{href="/permissions}, response.body
    end
  end

  # --- Probe 5 -------------------------------------------------------------

  test "host admin flag gates the engine when parent_controller is Admin::BaseController" do
    # noemail: full-access role but admin flag false
    grant_role!(users(:noemail), role: @owner_role)
    sign_in_as users(:noemail)

    get "/permissions/roles"
    assert_response :forbidden
    assert_includes response.body, "Admins only", "host require_admin! should run before the engine"
  end

  test "host admin without full access gets a reasoned 403 from the engine" do
    # 0.3.0 (#23): require_full_access! now raises AccessDenied(:not_full_access)
    # instead of head :forbidden (was FINDINGS F10's blank page). In this app the
    # host's inherited rescue_from renders its branded 403 — F9's "harmless here"
    # note is now load-bearing.
    sign_in_as users(:ada) # admin flag, no role at all
    get "/permissions/roles"
    assert_response :forbidden
    assert_equal "not_full_access", response.headers["X-Current-Scope-Reason"],
      "the engine 403 now carries a reason header like every other denial"
    assert_includes response.body, "not_full_access",
      "the host's branded 403 page renders (rescue_from AccessDenied is inherited by engine controllers)"
  end

  test "engine never inherits the parent controller's admin layout" do
    # Verified before the host override existed too: the engine rendered its own
    # cs-shell layout, NOT layout "admin" from Admin::BaseController.
    sign_in_as users(:olive)
    get "/permissions/roles"
    assert_response :success
    refute_includes response.body, "ADMIN-LAYOUT-MARKER",
      "engine must not inherit the parent controller's admin layout"
  end

  test "host retheme: app/views/layouts/current_scope/application.html.erb shadows the engine layout" do
    sign_in_as users(:olive)
    get "/permissions/roles"
    assert_response :success
    assert_includes response.body, "HOST-CS-OVERRIDE", "host layout override should win"
    refute_includes response.body, "cs-shell", "engine's own shell replaced by the override"
  end

  # --- Probe 6 -------------------------------------------------------------

  test "subject_label :email shows emails and falls back for a nil email" do
    sign_in_as users(:olive)
    get "/permissions/subjects"
    assert_response :success
    assert_includes response.body, "owner@example.com"
    assert_includes response.body, "No Email", "nil email should fall back to name"
  end

  test "subject_label pointing at a missing method silently falls back" do
    original = CurrentScope.config.subject_label
    CurrentScope.config.subject_label = :department # no such method on User
    sign_in_as users(:olive)
    get "/permissions/subjects"
    assert_response :success
    assert_includes response.body, "owner@example.com", "falls back to default chain, no error"
  ensure
    CurrentScope.config.subject_label = original
  end

  test "subject_label Proc that raises on one subject falls back instead of 500ing the page" do
    # 0.3.0 (#22/PR #54): the Proc form is now error-isolated per subject, like
    # the Symbol form always was (was FINDINGS F12's 500-the-whole-page trap).
    original = CurrentScope.config.subject_label
    CurrentScope.config.subject_label = ->(u) { u.email.upcase } # nil email → NoMethodError
    sign_in_as users(:olive)
    get "/permissions/subjects"
    assert_response :success
    assert_includes response.body, "OWNER@EXAMPLE.COM", "working subjects still use the Proc"
    assert_includes response.body, users(:noemail).name,
      "the nil-email subject falls back to the default chain instead of raising"
  ensure
    CurrentScope.config.subject_label = original
  end

  test "subject_label Proc form renders" do
    original = CurrentScope.config.subject_label
    CurrentScope.config.subject_label = ->(u) { "#{u.name} <#{u.email}>" }
    sign_in_as users(:olive)
    get "/permissions/subjects"
    assert_response :success
    assert_includes response.body, "Olive Owner &lt;owner@example.com&gt;"
  ensure
    CurrentScope.config.subject_label = original
  end

  # --- Probes 1 + 8: the grid ----------------------------------------------

  test "grid shows reports and admin/reports as separate rows with aligned cells" do
    sign_in_as users(:olive)
    get "/permissions/roles/#{@member_role.id}/edit"
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    rows = doc.css("table.cs-grid tbody tr")
    row_labels = rows.map { |r| r.at_css("th .cs-row-all span, th span")&.text&.strip }
    assert_includes row_labels, "reports"
    assert_includes row_labels, "admin/reports"

    header_count = doc.css("table.cs-grid thead th").size
    rows.each do |row|
      assert_equal header_count, row.css("th, td").size,
        "row #{row.at_css('th')&.text&.strip} misaligned"
    end
  end

  test "group naming an action routed on only one controller leaves blank cells elsewhere" do
    sign_in_as users(:olive)
    get "/permissions/roles/#{@member_role.id}/edit"
    doc = Nokogiri::HTML(response.body)

    headers = doc.css("table.cs-grid thead th").map { |h| h.text.strip }
    assert_includes headers, "workflow"

    # admin/reports has an approve checkbox in the workflow column…
    assert doc.at_css("input[value='admin/reports:workflow']"), "admin/reports workflow cell should be a checkbox"
    # …and sessions (no approve, no show) is blank there.
    workflow_index = headers.index("workflow")
    # 0.3.0 (#62): the row <th> can now carry a "gate not run" badge (sessions
    # skips the gate), so match the row-label span, not the whole th text.
    sessions_row = doc.css("table.cs-grid tbody tr").find { |r| r.at_css("th .cs-row-all span")&.text&.strip == "sessions" }
    sessions_cells = sessions_row.css("th, td")
    assert_includes sessions_cells[workflow_index]["class"].to_s, "cs-cell-blank"
  end

  test "an action in two groups renders two checkboxes controlling the same permission" do
    # dashboard routes only #show; "show" is in both the read and workflow groups.
    @member_role.update!(permission_keys: %w[dashboard#show])
    sign_in_as users(:olive)
    get "/permissions/roles/#{@member_role.id}/edit"
    doc = Nokogiri::HTML(response.body)

    read_box     = doc.at_css("input[value='dashboard:read']")
    workflow_box = doc.at_css("input[value='dashboard:workflow']")
    assert read_box, "dashboard read cell missing"
    assert workflow_box, "dashboard workflow cell missing"

    # Member role holds dashboard#show, so BOTH group checkboxes render checked —
    # one underlying permission presented as two independent-looking toggles.
    assert read_box["checked"], "read box should appear checked"
    assert workflow_box["checked"], "workflow box should appear checked (same single key)"
  end

  test "saving with only one of two overlapping groups checked still grants the shared key" do
    sign_in_as users(:olive)
    role = create_role!("OverlapProbe", [])

    patch "/permissions/roles/#{role.id}", params: {
      role: { name: "OverlapProbe", permission_groups: [ "dashboard:read" ], permission_keys: [ "" ] }
    }
    assert_response :redirect
    assert_includes role.reload.permission_keys, "dashboard#show"

    # Re-render: the OTHER group's checkbox now reads checked too.
    get "/permissions/roles/#{role.id}/edit"
    doc = Nokogiri::HTML(response.body)
    assert doc.at_css("input[value='dashboard:workflow']")["checked"],
      "unticked workflow group renders checked after saving read group"
  end

  # --- Probe 10: fit and finish --------------------------------------------

  test "host override restores a way back to the app (stock engine chrome has none)" do
    # Pre-override, this asserted refute_match %r{href="/"} and PASSED: the
    # engine's own layout has no link back to the host app at all.
    sign_in_as users(:olive)
    get "/permissions/roles"
    assert_response :success
    assert_match %r{href="/"}, response.body
  end
end
