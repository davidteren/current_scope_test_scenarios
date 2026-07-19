require "test_helper"

# Scenarios 1-5: baseline veto, SoD off, missing hook, nil-record foot-gun,
# collection-action hole.
class SodMatrixTest < ActionDispatch::IntegrationTest
  include SodMatrixSetup

  setup do
    create_people_and_roles
    grant_role!(@alice, role: @owner)      # full access
    grant_role!(@bob, role: @approver)
    @own = Expense.create!(description: "Alice's own", amount_cents: 100, requested_by: @alice)
  end

  teardown { ExpensesController.simulate_nil_record = false }

  # --- 1. baseline veto -----------------------------------------------------

  test "1a: full-access initiator approving own expense is vetoed with 403 + sod_veto reason" do
    sign_in @alice
    post approve_expense_path(@own)
    assert_response :forbidden
    assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
  end

  test "1b: non-initiator with a grant may approve" do
    sign_in @bob
    post approve_expense_path(@own)
    assert_response :success
    assert_nil response.headers["X-Current-Scope-Reason"]
  end

  test "1c: denial is rescued by the engine (403, not 500) and signed-out users get no_grant" do
    get expenses_path   # not signed in at all
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  # --- 2. SoD off -----------------------------------------------------------

  test "2: with sod_actions empty the same self-approval sails through, no hook needed anywhere" do
    with_config(sod_actions: []) do
      sign_in @alice
      post approve_expense_path(@own)
      assert_response :success

      # Invoice has NO current_scope_initiator and that's fine with SoD off.
      invoice = Invoice.create!(description: "v", amount_cents: 1, requested_by: @alice)
      post approve_invoice_path(invoice)
      assert_response :success
    end
  end

  # --- 3. missing hook: loud, not open ---------------------------------------

  test "3a: SoD action on a record class without current_scope_initiator raises ConfigurationError" do
    invoice = Invoice.create!(description: "v", amount_cents: 1, requested_by: @bob)
    sign_in @alice
    error = assert_raises(CurrentScope::ConfigurationError) { post approve_invoice_path(invoice) }
    assert_match(/Invoice#current_scope_initiator is not defined/, error.message)
    assert_match(/invoices#approve/, error.message)
    assert_match(/return nil to exempt/, error.message)
    assert_match(/remove "approve" from config.sod_actions/, error.message)
  end

  test "3b: a hook returning nil exempts the record type - allowed" do
    invoice = Invoice.create!(description: "v", amount_cents: 1, requested_by: @bob)
    Invoice.define_method(:current_scope_initiator) { nil }
    sign_in @bob
    post approve_invoice_path(invoice)
    assert_response :success
  ensure
    Invoice.remove_method(:current_scope_initiator)
  end

  # --- 4. the nil-record foot-gun --------------------------------------------

  test "4a: current_scope_record returning nil on a member action silently skips the veto" do
    ExpensesController.simulate_nil_record = true
    sign_in @alice
    post approve_expense_path(@own)
    assert_response :success   # veto SKIPPED - initiator self-approved
  end

  test "4b: warn_on_nil_sod_record logs the nudge to the Rails log" do
    ExpensesController.simulate_nil_record = true
    log_file = Rails.root.join("log/test.log")
    offset = File.size(log_file)
    with_config(warn_on_nil_sod_record: true) do
      sign_in @alice
      post approve_expense_path(@own)
      assert_response :success
    end
    logged = File.read(log_file, mode: "rb")[offset..].to_s
    assert_match(/\[CurrentScope\] "expenses#approve" is a separation-of-duties action but was gated with a nil record/, logged)
  end

  # --- 5. collection action in sod_actions -----------------------------------

  test "5: approve_all with a legitimately nil record lets the initiator bulk-approve their own expense" do
    with_config(sod_actions: %w[approve approve_all]) do
      Expense.create!(description: "Bob's own", amount_cents: 5, requested_by: @bob)
      sign_in @bob
      post approve_all_expenses_path
      assert_response :success   # bob's own expense included, no veto
      assert_match(/approved all/, response.body)
    end
  end
end
