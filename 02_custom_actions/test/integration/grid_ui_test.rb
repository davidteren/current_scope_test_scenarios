require "test_helper"

# Probe 2: the role-edit permission grid under three permission_grid_groups
# configurations. Fetched over HTTP as a full-access subject.
class GridUiTest < ActionDispatch::IntegrationTest
  setup do
    seed_roles!
    grant_role!(users(:alice), role: @owner_role)
    sign_in users(:alice)
    @role = make_role!("GridProbe", [])
  end

  def with_grid_groups(groups)
    old = CurrentScope.config.permission_grid_groups
    CurrentScope.config.permission_grid_groups = groups
    yield
  ensure
    CurrentScope.config.permission_grid_groups = old
  end

  def header_labels
    response.parsed_body.css("table.cs-grid thead th").map { |th| th.text.strip }
  end

  def row_controllers
    # 0.3.0 (#62): provably-ungated rows carry a "gate not run" badge inside the
    # row <th>; strip it so this returns just the controller names.
    response.parsed_body.css("table.cs-grid tbody tr th").map do |th|
      th = th.dup
      th.css(".cs-ungated-badge").each(&:remove)
      th.text.strip
    end
  end

  def badged_controllers
    response.parsed_body.css("table.cs-grid tbody tr th")
            .select { |th| th.at_css(".cs-ungated-badge") }
            .map { |th| th.dup.tap { |d| d.css(".cs-ungated-badge").each(&:remove) }.text.strip }
  end

  test "default CRUD groups: every custom action becomes its own column (wide grid)" do
    get "/current_scope/roles/#{@role.id}/edit"
    assert_response :success

    labels = header_labels
    # Corner + 4 CRUD groups + 13 leftover custom/wizard actions = 18 header cells
    assert_equal "Controller", labels.first
    %w[read create update destroy].each { |g| assert_includes labels, g }
    %w[approve archive bulk_archive clone complete export preview_all publish
       reject search step_one step_two submit_step_one].each do |a|
      assert_includes labels, a, "custom action #{a} missing its own column"
    end
    assert_equal 18, labels.size, "expected 18 header cells, got #{labels.size}: #{labels}"
    assert_equal %w[legacy reports sessions wizard], row_controllers
    # 0.3.0 (#62): sessions skips the gate, so its row is badged "gate not run".
    assert_equal %w[sessions], badged_controllers
  end

  test "permission_grid_groups = nil: every raw action its own column" do
    with_grid_groups(nil) do
      get "/current_scope/roles/#{@role.id}/edit"
      assert_response :success
      labels = header_labels
      # Corner + 20 distinct raw action names across reports/sessions/wizard
      assert_equal 21, labels.size, "got #{labels.size}: #{labels}"
      %w[new edit index show approve step_one].each { |a| assert_includes labels, a }
      assert_not_includes labels, "read"
    end
  end

  test "custom workflow group folds approve/reject/publish into one column" do
    with_grid_groups({ "workflow" => %w[approve reject publish] }) do
      get "/current_scope/roles/#{@role.id}/edit"
      assert_response :success
      labels = header_labels
      assert_includes labels, "workflow"
      assert_not_includes labels, "approve"
      assert_not_includes labels, "reject"
      assert_not_includes labels, "publish"
      # everything else (CRUD included, since the custom hash REPLACED the default) is raw
      assert_includes labels, "index"
      assert_includes labels, "new"
    end
  end

  test "ticking the workflow group grants all three actions" do
    with_grid_groups({ "workflow" => %w[approve reject publish] }) do
      patch "/current_scope/roles/#{@role.id}", params: {
        role: { name: "GridProbe", permission_groups: [ "", "reports:workflow" ], permission_keys: [ "" ] }
      }
      assert_redirected_to "/current_scope/roles"
      assert_equal %w[reports#approve reports#publish reports#reject],
                   @role.reload.permission_keys.sort
    end
  end

  test "non-full-access subject cannot enter the management UI" do
    sign_in users(:bob)   # Member, not full access
    get "/current_scope/roles"
    assert_response :forbidden
  end
end
