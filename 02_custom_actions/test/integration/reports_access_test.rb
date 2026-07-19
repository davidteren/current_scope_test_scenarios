require "test_helper"

# Probes 3 + 4: single-custom-action grants, fail-closed everywhere else,
# per-record scoped grants via current_scope_record.
class ReportsAccessTest < ActionDispatch::IntegrationTest
  setup { seed_roles! }

  test "org-wide grant of exactly reports#approve: approve allowed, everything else fail-closed" do
    grant_role!(users(:dave), role: make_role!("Approver", %w[reports#approve]))
    sign_in users(:dave)

    post approve_report_path(reports(:q2))   # q2 requested by bob, no SoD conflict
    assert_redirected_to report_path(reports(:q2))
    assert_equal "approved", reports(:q2).reload.state

    post reject_report_path(reports(:q2))
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]

    patch report_path(reports(:q2)), params: { report: { title: "hax" } }
    assert_response :forbidden

    post clone_report_path(reports(:q2))
    assert_response :forbidden

    get reports_path
    assert_response :forbidden

    get "/reports/search", params: { q: "Budget" }
    assert_response :forbidden
  end

  test "scoped grant on ONE report allows approve on that record only" do
    role = make_role!("ScopedApprover", %w[reports#approve])
    grant_scoped_role!(users(:carol), role: role, record: reports(:q2))
    sign_in users(:carol)

    post approve_report_path(reports(:q2))
    assert_redirected_to report_path(reports(:q2))

    post approve_report_path(reports(:q1))
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "scoped grant reaches clone (custom member action gets the record)" do
    role = make_role!("ScopedCloner", %w[reports#clone])
    grant_scoped_role!(users(:carol), role: role, record: reports(:q2))
    sign_in users(:carol)

    assert_difference "Report.count", 1 do
      post clone_report_path(reports(:q2))
    end

    post clone_report_path(reports(:q1))
    assert_response :forbidden
  end

  test "scoped grant does NOT unlock collection actions via ?id= smuggling" do
    role = make_role!("ScopedApprover2", %w[reports#approve reports#export])
    grant_scoped_role!(users(:carol), role: role, record: reports(:q2))
    sign_in users(:carol)

    # export is a collection action; a scoped grant must not satisfy it even
    # with ?id= in the query string.
    get export_reports_path, params: { id: reports(:q2).id }
    assert_response :forbidden
  end

  test "signed-out and no-role users are denied (fail closed) with a bare 403" do
    get reports_path
    assert_response :forbidden

    sign_in users(:carol) # no role at all
    get reports_path
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
  end

  test "owner can run every custom action on records they did not initiate" do
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)

    post publish_report_path(reports(:q2))
    assert_redirected_to report_path(reports(:q2))

    patch archive_report_path(reports(:q2))
    assert_redirected_to report_path(reports(:q2))

    get export_reports_path
    assert_response :success

    post bulk_archive_reports_path
    assert_redirected_to reports_path

    get preview_all_reports_path
    assert_response :success

    get "/reports/search", params: { q: "Budget" }
    assert_response :success
    assert_match "search[GET]", response.body

    post "/reports/search", params: { q: "Budget" }
    assert_response :success
    assert_match "search[POST]", response.body
  end
end
