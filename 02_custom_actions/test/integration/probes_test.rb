require "test_helper"

# Extra probes capturing observed behavior (feeds FINDINGS.md).
class ProbesTest < ActionDispatch::IntegrationTest
  setup { seed_roles! }

  test "root login page works signed-out (skip_before_action)" do
    get root_path
    assert_response :success
    assert_includes response.body, "Login as"
  end

  test "PROBE: denial body is completely empty (bare head :forbidden)" do
    sign_in users(:carol)
    get reports_path
    assert_response :forbidden
    assert_equal "", response.body, "expected an empty 403 body"
  end

  test "PROBE: programmatic grant of a typo'd key is rejected loudly" do
    # 0.3.0 (#20): unknown keys make the role invalid instead of being silently
    # dropped; assign_permission_keys(..., scrub: true) is the opt-in old behavior.
    role = CurrentScope::Role.create!(name: "Typo")
    role.permission_keys = %w[reports#aprove reports#approve]   # first is a typo
    error = assert_raises(ActiveRecord::RecordInvalid) { role.save! }
    assert_match "reports#aprove", error.message

    role.assign_permission_keys(%w[reports#aprove reports#approve], scrub: true)
    role.save!
    assert_equal %w[reports#approve], role.reload.permission_keys,
                 "scrub: true restores the drop-quietly behavior, deliberately"
    assert_equal %w[reports#aprove], role.permission_keys_change[:rejected]
  end

  test "PROBE: unauthenticated 403 vs 404 leaks record existence on member actions" do
    # No login at all. Existing record id -> 403 (gate denies after the hook
    # loaded the record). Missing id -> RecordNotFound -> 404. Divergence =
    # existence oracle for anonymous users.
    post approve_report_path(reports(:q2))
    existing_status = response.status

    post "/reports/999999/approve"
    missing_status = response.status

    assert_equal 403, existing_status
    assert_equal 404, missing_status
    assert_not_equal existing_status, missing_status,
                     "status divergence: anonymous callers can enumerate report ids"
  end

  test "PROBE: grid blank-cell density with default groups" do
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)
    role = make_role!("DensityProbe", [])

    get "/current_scope/roles/#{role.id}/edit"
    doc = response.parsed_body
    blanks = doc.css("table.cs-grid tbody td.cs-cell-blank").size
    cells  = doc.css("table.cs-grid tbody td").size
    # 3 controllers x 17 action columns = 51 cells; most are blank.
    assert_operator blanks, :>, cells / 2,
                    "grid is majority blank cells (#{blanks}/#{cells}) — sparse matrix"
    puts "\n[PROBE] grid cells=#{cells} blank=#{blanks} (#{(100.0 * blanks / cells).round}% blank)"
  end

  test "PROBE: a host rescue_from StandardError registered after Guard turns denials into 500s" do
    sign_in users(:carol)   # no role -> should be a 403 denial
    get "/legacy"
    assert_response :internal_server_error
    assert_equal "our custom 500 page", response.body
    assert_nil response.headers["X-Current-Scope-Reason"],
               "reason header lost when the host handler swallows AccessDenied"
  end

  test "PROBE: engine management-UI 403 carries X-Current-Scope-Reason: not_full_access" do
    # 0.3.0 (#23): require_full_access! now raises AccessDenied like every other
    # denial, so the console 403 carries the reason header and a short page.
    sign_in users(:bob)   # Member, not full access
    get "/current_scope/roles"
    assert_response :forbidden
    assert_equal "not_full_access", response.headers["X-Current-Scope-Reason"]
  end

  test "PROBE: skipped-gate controller still occupies the grid as grantable rows" do
    # sessions skips the gate entirely, yet sessions#index/create/destroy are
    # catalog entries an admin can tick — the ticks change nothing.
    assert_includes CurrentScope.catalog.keys, "sessions#index"
    assert_includes CurrentScope.catalog.keys, "sessions#create"
  end
end
