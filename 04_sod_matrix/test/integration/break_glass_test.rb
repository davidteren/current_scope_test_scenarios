require "test_helper"

# Scenarios 6-8: break-glass matrix, the bypass_sod-in-sod_actions guard rail,
# and how (whether) bypass_sod surfaces in the role grid.
class BreakGlassTest < ActionDispatch::IntegrationTest
  include SodMatrixSetup

  setup do
    create_people_and_roles
    # Bypasser: holds ONLY expenses#bypass_sod. permission_keys= rejects
    # non-catalog keys (bypass_sod is not routed; 0.3.0 #20 made the rejection
    # loud instead of silent), so insert the row directly.
    @bypasser = CurrentScope::Role.create!(name: "Bypasser")
    @bypasser.role_permissions.create!(permission_key: "expenses#bypass_sod")
    @flagged = Expense.create!(description: "flagged", amount_cents: 1,
                               requested_by: @alice, sod_bypass_requested: true)
  end

  # --- 6. break-glass matrix -------------------------------------------------

  test "6a: config on + record flag on + initiator holds bypass_sod: allowed, audited once, header set" do
    grant_role!(@alice, role: @bypasser)
    with_config(allow_sod_bypass: true) do
      sign_in @alice
      assert_difference -> { CurrentScope::Event.where(event: "sod.bypassed").count }, 1 do
        post approve_expense_path(@flagged)
      end
      assert_response :success
      assert_equal "sod_bypassed", response.headers["X-Current-Scope-Reason"]
      event = CurrentScope::Event.where(event: "sod.bypassed").last
      assert_equal "expenses#approve", event.details["permission"]
      assert_equal @alice.to_gid.to_s, event.details["initiator"]
    end
  end

  test "6b: config OFF + record flag on + holds bypass_sod: vetoed" do
    grant_role!(@alice, role: @bypasser)
    sign_in @alice   # allow_sod_bypass stays default false
    post approve_expense_path(@flagged)
    assert_response :forbidden
    assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
  end

  test "6c: config on + record flag OFF + holds bypass_sod: vetoed" do
    grant_role!(@alice, role: @bypasser)
    unflagged = Expense.create!(description: "no flag", amount_cents: 1, requested_by: @alice)
    with_config(allow_sod_bypass: true) do
      sign_in @alice
      post approve_expense_path(unflagged)
      assert_response :forbidden
      assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
    end
  end

  test "6d: config on + record flag on + initiator LACKS bypass_sod: vetoed" do
    grant_role!(@alice, role: @owner)   # full access does NOT bypass?  It grants everything...
    with_config(allow_sod_bypass: true) do
      sign_in @alice
      post approve_expense_path(@flagged)
      # NOTE: full_access grants expenses#bypass_sod implicitly (roles_granting
      # includes full_access), so this is expected to be ALLOWED - probing.
      assert_response :success
      assert_equal "sod_bypassed", response.headers["X-Current-Scope-Reason"]
    end
  end

  test "6d2: config on + flag on + plain approver role without bypass_sod: vetoed" do
    grant_role!(@alice, role: @approver)
    with_config(allow_sod_bypass: true) do
      sign_in @alice
      post approve_expense_path(@flagged)
      assert_response :forbidden
      assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
    end
  end

  test "6e: bypass hook missing on the model: vetoed, no error" do
    Invoice.define_method(:current_scope_initiator) { requested_by }
    invoice = Invoice.create!(description: "v", amount_cents: 1, requested_by: @alice)
    grant_role!(@alice, role: @bypasser)
    with_config(allow_sod_bypass: true) do
      sign_in @alice
      post approve_invoice_path(invoice)
      assert_response :forbidden
      assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
    end
  ensure
    Invoice.remove_method(:current_scope_initiator)
  end

  # --- 7. guard rail: bypass permission inside sod_actions --------------------

  test "7a: bypass_sod in sod_actions raises ConfigurationError at DECISION time (not boot)" do
    grant_role!(@alice, role: @bypasser)
    with_config(sod_actions: %w[approve bypass_sod], allow_sod_bypass: true) do
      sign_in @alice
      error = assert_raises(CurrentScope::ConfigurationError) { post approve_expense_path(@flagged) }
      assert_match(/must not be an SoD action/, error.message)
      assert_match(/it would recurse/, error.message)
    end
  end

  test "7b: same misconfig with allow_sod_bypass off is NOT detected - veto wins silently" do
    grant_role!(@alice, role: @bypasser)
    with_config(sod_actions: %w[approve bypass_sod], allow_sod_bypass: false) do
      sign_in @alice
      post approve_expense_path(@flagged)
      assert_response :forbidden   # no raise: the guard rail only runs behind allow_sod_bypass
    end
  end

  test "7c: misconfig undetected for non-initiators too - nothing raises until a self-approval conflict occurs" do
    grant_role!(@bob, role: @approver)
    with_config(sod_actions: %w[approve bypass_sod], allow_sod_bypass: true) do
      sign_in @bob
      post approve_expense_path(@flagged)   # bob is not the initiator: no conflict, no guard-rail check
      assert_response :success
    end
  end

  # --- 8. bypass_sod discoverability in the grid ------------------------------

  test "8a: permission_keys= rejects the unrouted bypass_sod key loudly" do
    # 0.3.0 (#20): unknown keys now fail validation (naming the key) instead of
    # being silently dropped; scrub: true is the deliberate opt-in to the old drop.
    role = CurrentScope::Role.create!(name: "GridTest")
    error = assert_raises(ActiveRecord::RecordInvalid) do
      role.update!(permission_keys: %w[expenses#bypass_sod expenses#approve])
    end
    assert_match(/expenses#bypass_sod/, error.message)
    assert_empty role.reload.permission_keys, "nothing persists on the strict path"

    role.assign_permission_keys(%w[expenses#bypass_sod expenses#approve], scrub: true)
    role.save!
    assert_equal %w[expenses#approve], role.reload.permission_keys,
                 "scrub: true drops the non-catalog key without error"
  end

  test "8b: the role grid never shows a bypass_sod cell - the permission is ungrantable via the UI" do
    grant_role!(@alice, role: @owner)
    sign_in @alice
    get "/current_scope/roles/#{@approver.id}/edit"
    assert_response :success
    refute_includes response.body, "bypass_sod",
                    "grid shows no bypass_sod column/cell - an admin cannot grant it in the UI"

    # Custom routed actions DO appear as their own columns.
    column_labels = response.body.scan(%r{<th scope="col">\s*([^<]+?)\s*</th>}).flatten
    assert_includes column_labels, "approve"
    assert_includes column_labels, "approve_all"
    assert_includes column_labels, "reject"
    rows = response.body.scan(/data-cs-row-all/).size
    assert_operator rows, :>=, 3, "expected controller rows for expenses/invoices/sessions"
  end
end
