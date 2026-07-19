require "test_helper"

# Probe 3: grid usability at god-controller scale. Fetch the role editor as a
# full-access Owner and measure the matrix.
class GridUiTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(name: "Grid Greta", email: "greta@example.com")
    make_owner!(@owner)
    login_as @owner
    @member = CurrentScope::Role.find_by!(name: "Member")
  end

  test "non-owner cannot enter the management UI" do
    pleb = User.create!(name: "Pleb", email: "pleb@example.com")
    login_as pleb
    get "/current_scope/roles"
    assert_response :forbidden
  end

  test "owner can enter and the grid renders" do
    get "/current_scope/roles/#{@member.id}/edit"
    assert_response :success
    assert_includes response.body, "cs-grid"
  end

  test "MEASURE: host permission_grid_groups fold god-controller one-offs" do
    get "/current_scope/roles/#{@member.id}/edit"
    doc = Nokogiri::HTML(response.body)

    header_cells = doc.css("table.cs-grid thead th")
    rows = doc.css("table.cs-grid tbody tr")
    one_off_columns = header_cells[1..].map(&:text).map(&:strip)
    grouped = one_off_columns & CurrentScope.config.permission_grid_groups.keys

    puts "\n=== GRID MEASUREMENTS ==="
    puts "columns (incl. controller col): #{header_cells.size}"
    puts "group columns: #{grouped.inspect}"
    puts "one-off action columns: #{(one_off_columns - grouped).size}"
    puts "rows (controllers): #{rows.size} -> #{doc.css('table.cs-grid tbody th[scope=row]').map(&:text).map(&:strip).inspect}"
    puts "cells total: #{doc.css('table.cs-grid tbody td').size}"
    blank = doc.css("table.cs-grid tbody td").count { |td| td.css("input[type=checkbox]").empty? }
    puts "blank cells: #{blank}"
    col_px = one_off_columns.sum { |l| [ l.length * 6.9, 34 ].max + 21 }
    est_width = (160 + col_px).round
    puts "longest header: #{one_off_columns.max_by(&:length).inspect}"
    puts "estimated table min-width (nowrap headers): ~#{est_width}px (~#{(est_width / 1280.0).round(1)}x a 1280px viewport)"
    puts "page bytes: #{response.body.bytesize}"
    puts "=========================="

    # Host groups (reports/export/bulk/read/create/update/destroy) collapse the
    # previous ~30+ one-off columns into a compact matrix (ie-audit P1 / F4).
    assert_includes grouped, "reports"
    assert_includes grouped, "export"
    assert_includes grouped, "bulk"
    assert_operator header_cells.size, :<=, 12,
      "expected grouped grid to stay well under the ungrouped 30+ column surface, got #{header_cells.size}"
    assert_operator (one_off_columns - grouped).size, :<=, 3,
      "expected almost all legacy verbs to land in a group"
  end
end
