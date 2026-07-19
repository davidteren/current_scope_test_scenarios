require "test_helper"

# Scenarios 9-10: sod_identity under impersonation, audit tri-state.
class ImpersonationAndAuditTest < ActionDispatch::IntegrationTest
  include SodMatrixSetup

  setup do
    create_people_and_roles
    grant_role!(@alice, role: @owner)
    grant_role!(@bob, role: @approver)
    @alices = Expense.create!(description: "Alice's own", amount_cents: 9, requested_by: @alice)
  end

  # --- 9. sod_identity -------------------------------------------------------

  test "9a: :either vetoes the real actor's own record even while impersonating" do
    sign_in @alice
    impersonate @bob
    post approve_expense_path(@alices)   # subject=bob (granted), actor=alice (initiator)
    assert_response :forbidden
    assert_equal "sod_veto", response.headers["X-Current-Scope-Reason"]
  end

  test "9b: :subject weighs only the effective subject - impersonated approval passes" do
    with_config(sod_identity: :subject) do
      sign_in @alice
      impersonate @bob
      post approve_expense_path(@alices)
      assert_response :success
    end
  end

  # --- 10. audit tri-state ---------------------------------------------------

  test "10a: audit=false records nothing on an engine-UI grant" do
    carol = User.create!(name: "Carol", email: "carol@x.com")
    with_config(audit: false) do
      sign_in @alice
      assert_no_difference -> { CurrentScope::Event.count } do
        # 0.3.0 (#85): engine route standardized to plural `resources :role_assignments`.
        post "/current_scope/role_assignments",
             params: { subject_gid: carol.to_gid.to_s, role_id: @approver.id }
      end
      assert_response :redirect
    end
    assert_equal @approver, CurrentScope::RoleAssignment.find_by(subject: carol).role
  end

  test "10b: audit=true records org_role.assigned with actor attribution" do
    carol = User.create!(name: "Carol", email: "carol@x.com")
    sign_in @alice
    assert_difference -> { CurrentScope::Event.where(event: "org_role.assigned").count }, 1 do
      post "/current_scope/role_assignments",
           params: { subject_gid: carol.to_gid.to_s, role_id: @approver.id }
    end
    event = CurrentScope::Event.where(event: "org_role.assigned").last
    assert_equal @alice.to_gid.to_s, event.actor
    assert_equal carol.to_gid.to_s, event.target
  end

  test "10c: audit=:strict with the events table present behaves normally" do
    carol = User.create!(name: "Carol", email: "carol@x.com")
    with_config(audit: :strict) do
      sign_in @alice
      assert_difference -> { CurrentScope::Event.count }, 1 do
        post "/current_scope/role_assignments",
             params: { subject_gid: carol.to_gid.to_s, role_id: @approver.id }
      end
    end
  end

  test "10d: missing events table - audit=true degrades (grant commits), :strict raises and rolls back" do
    carol = User.create!(name: "Carol", email: "carol@x.com")
    conn = ActiveRecord::Base.connection
    conn.rename_table(:current_scope_events, :cse_hidden)
    CurrentScope::Event.reset_column_information

    sign_in @alice
    post "/current_scope/role_assignments",
         params: { subject_gid: carol.to_gid.to_s, role_id: @approver.id }
    assert_response :redirect, "audit=true must degrade gracefully on a missing events table"
    assert_equal @approver, CurrentScope::RoleAssignment.find_by(subject: carol).role

    dave = User.create!(name: "Dave", email: "dave@x.com")
    with_config(audit: :strict) do
      assert_raises(ActiveRecord::StatementInvalid) do
        post "/current_scope/role_assignments",
             params: { subject_gid: dave.to_gid.to_s, role_id: @approver.id }
      end
      assert_nil CurrentScope::RoleAssignment.find_by(subject: dave),
                 ":strict must roll the grant back rather than commit unaudited"
    end
  ensure
    conn.rename_table(:cse_hidden, :current_scope_events) if conn.table_exists?(:cse_hidden)
    CurrentScope::Event.reset_column_information
  end
end
