require "test_helper"

# Validates host-side fixes for ie-audit P1 findings on 03_god_controller.
# Fat-controller / ad-hoc route table (P1 #9–#10) stay intentional fixtures.
class P1HostFixesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(name: "P1 Owner", email: "p1owner@example.com")
    make_owner!(@owner)
    login_as @owner
  end

  test "flash notice from a legacy redirect is rendered in the layout" do
    post "/legacy/import"
    assert_redirected_to "/legacy/dashboard"
    follow_redirect!
    assert_select "p.flash-notice[role=status]", text: /imported/
  end

  test "flash alert from require_login is rendered after redirect to sessions" do
    delete "/logout"
    get "/legacy/dashboard"
    assert_redirected_to sessions_path
    follow_redirect!
    assert_select "p.flash-alert[role=alert]", text: /Log in first/
  end

  test "bulk_delete removes inactive customers (sibling of bulk_update)" do
    keep = Customer.create!(name: "KeepMe", active: true)
    gone = Customer.create!(name: "GoneMe", active: false)

    assert_difference -> { Customer.count }, -1 do
      post "/legacy/bulk_delete"
    end
    assert_redirected_to "/legacy/dashboard"
    assert Customer.exists?(keep.id)
    refute Customer.exists?(gone.id)
  end

  test "deny_all marks pending orders denied (sibling of approve_all)" do
    pending = Order.create!(number: "P1-DENY", status: "pending", archived: false)
    approved = Order.create!(number: "P1-OK", status: "approved", archived: false)

    post "/legacy/deny_all"
    assert_redirected_to "/legacy/dashboard"
    assert_equal "denied", pending.reload.status
    assert_equal "approved", approved.reload.status
  end

  test "assign and unassign flip Customer#assigned" do
    c = Customer.create!(name: "AssignMe", active: true, assigned: false)

    post "/legacy/#{c.id}/assign"
    assert_redirected_to "/legacy/dashboard"
    assert c.reload.assigned

    post "/legacy/#{c.id}/unassign"
    assert_redirected_to "/legacy/dashboard"
    refute c.reload.assigned
  end

  test "import creates a customer row" do
    assert_difference -> { Customer.count }, +1 do
      post "/legacy/import"
    end
  end

  test "update_settings persists site_name via Setting" do
    post "/legacy/update_settings", params: { site_name: "Acme HQ" }
    assert_redirected_to "/legacy/settings"
    assert_equal "Acme HQ", Setting["site_name"]

    get "/legacy/settings"
    assert_response :success
    assert_select "input#site_name[value=?]", "Acme HQ"
  end

  test "email_report records a ReportDelivery for the current user" do
    assert_difference -> { ReportDelivery.count }, +1 do
      post "/legacy/email_report"
    end
    delivery = ReportDelivery.order(:id).last
    assert_equal "legacy_email_report", delivery.kind
    assert_equal @owner.id, delivery.user_id
  end

  test "merge_records renames inactive customers" do
    inactive = Customer.create!(name: "OldName", active: false)
    active = Customer.create!(name: "LiveName", active: true)

    post "/legacy/merge_records"
    assert_equal "Merged", inactive.reload.name
    assert_equal "LiveName", active.reload.name
  end

  test "archive_old only archives orders older than the cutoff" do
    old = Order.create!(number: "OLD-1", status: "ok", archived: false, created_at: 45.days.ago)
    recent = Order.create!(number: "NEW-1", status: "ok", archived: false, created_at: 1.day.ago)

    post "/legacy/archive_old"
    assert old.reload.archived
    refute recent.reload.archived
  end

  test "purge deletes archived orders only" do
    archived = Order.create!(number: "ARCH-1", status: "ok", archived: true)
    live = Order.create!(number: "LIVE-1", status: "ok", archived: false)

    assert_difference -> { Order.count }, -1 do
      post "/legacy/purge"
    end
    refute Order.exists?(archived.id)
    assert Order.exists?(live.id)
  end

  test "denied mutating actions do not change row state" do
    roleless = User.create!(name: "P1 Roleless", email: "p1roleless@example.com")
    login_as roleless
    customer = Customer.create!(name: "Safe", active: false)
    order = Order.create!(number: "SAFE-1", status: "pending", archived: false)

    post "/legacy/bulk_update"
    assert_response :forbidden
    refute customer.reload.active

    post "/legacy/approve_all"
    assert_response :forbidden
    assert_equal "pending", order.reload.status

    post "/legacy/archive_old"
    assert_response :forbidden
    refute order.reload.archived
  end

  test "turbo_stream denials render the friendly page, not a blank body" do
    roleless = User.create!(name: "Turbo Roleless", email: "turbo-roleless@example.com")
    login_as roleless
    post "/legacy/update_settings",
         params: { site_name: "Nope" },
         headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    assert_response :forbidden
    assert_equal "no_grant", response.headers["X-Current-Scope-Reason"]
    assert_includes response.body, "Access denied"
    assert_includes response.body, "no_grant"
  end

  test "bulk_delete and merge_records treat NULL active as inactive" do
    null_active = Customer.create!(name: "NullActive", active: nil)
    post "/legacy/merge_records"
    assert_equal "Merged", null_active.reload.name

    post "/legacy/bulk_delete"
    refute Customer.exists?(null_active.id)
  end

  test "Setting.[]= upserts without raising on a second write to the same key" do
    assert_equal "one", (Setting["site_name"] = "one")
    assert_equal "two", (Setting["site_name"] = "two")
    assert_equal 1, Setting.where(key: "site_name").count
    assert_equal "two", Setting["site_name"]
  end
end

