require "test_helper"

# Probe 6: scope_for(Report, permission: :approve) returns exactly the
# approvable set.
class ScopeForTest < ActiveSupport::TestCase
  setup { seed_roles! }

  def helper = Object.new.extend(CurrentScope::Permissions)

  test "scoped approve grant lists exactly that record" do
    role = make_role!("ScopedApprover", %w[reports#approve])
    grant_scoped_role!(users(:carol), role: role, record: reports(:q2))

    with_current_user(users(:carol)) do
      assert_equal [ reports(:q2) ], helper.scope_for(Report, permission: :approve).to_a
      assert_empty helper.scope_for(Report).to_a, "index not granted -> empty"
    end
  end

  test "org-wide approve grant lists every report" do
    grant_role!(users(:dave), role: make_role!("Approver", %w[reports#approve]))
    with_current_user(users(:dave)) do
      assert_equal Report.count, helper.scope_for(Report, permission: :approve).count
    end
  end

  test "no subject / no grant -> empty, chainable" do
    with_current_user(nil) do
      rel = helper.scope_for(Report, permission: :approve)
      assert_empty rel.to_a
      assert_empty rel.where(state: "draft").to_a   # still chainable
    end
  end

  test "DOCUMENTED DRIFT: scope_for ignores SoD, so an initiator's own record is listed as approvable" do
    grant_role!(users(:alice), role: @owner_role)
    with_current_user(users(:alice)) do
      listed = helper.scope_for(Report, permission: :approve).to_a
      assert_includes listed, reports(:q1), "own record listed by scope_for"
      assert_not helper.allowed_to?(:approve, reports(:q1)), "...but the gate vetoes it"
    end
  end
end
