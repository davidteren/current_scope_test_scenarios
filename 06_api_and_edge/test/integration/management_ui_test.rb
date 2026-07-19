require "test_helper"

# Engine management UI probes: entry gating + what the grid renders for
# phantom (ghosts) and ungated (api/health) controllers, and the custom
# publish action.
class ManagementUiTest < ActionDispatch::IntegrationTest
  setup { create_users_and_roles! }

  test "only full-access subjects enter the management UI" do
    get "/current_scope/"
    assert_response :forbidden

    post "/sessions", params: { user_id: @member.id }
    get "/current_scope/"
    assert_response :forbidden
    # 0.3.0 (#23): papercut fixed — engine UI denial now raises AccessDenied
    # like every other denial, so it carries a machine-readable reason header.
    assert_equal "not_full_access", response.headers["X-Current-Scope-Reason"]

    post "/sessions", params: { user_id: @owner.id }
    get "/current_scope/"
    assert_response :success
  end

  test "grid structure dump (columns, rows, ghost row raw HTML)" do
    post "/sessions", params: { user_id: @owner.id }
    get "/current_scope/roles/#{@member_role.id}/edit"
    assert_response :success

    html = response.body
    rows = html.scan(%r{<tr[^>]*>.*?</tr>}m)
    puts "\n=== GRID DUMP: #{rows.size} <tr> rows ==="
    rows.each do |r|
      cells = r.scan(%r{<t[hd][^>]*>(.*?)</t[hd]>}m).flatten.map { |c| c.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip }
      puts cells.inspect
    end
    ghost_row = rows.find { |r| r.include?("ghosts") }
    puts "\n=== RAW GHOST ROW ===\n#{ghost_row}\n=== END ==="
  end

  test "grid renders phantom + ungated controllers as grantable rows" do
    post "/sessions", params: { user_id: @owner.id }
    get "/current_scope/roles/#{@member_role.id}/edit"
    assert_response :success

    body = response.body
    assert_includes body, "ghosts", "phantom controller (no class) still gets a grid row"
    assert_includes body, "api/health", "ungated tripwire-only controller still gets a grid row"
    assert_includes body, "api/halted", "ungated controller with the before_action leak gets a row"
    assert_includes body, "publish", "custom member action appears in the grid"
  end
end
