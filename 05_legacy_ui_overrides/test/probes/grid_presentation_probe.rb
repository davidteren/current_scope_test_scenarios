# Run with: RAILS_ENV=test bin/rails runner test/probes/grid_presentation_probe.rb
# Evidence for probes 1 + 8: how the grid presents the duplicate reports
# controllers and the custom groups.
require "action_dispatch/testing/integration"

CurrentScope.seed_defaults!
owner = User.create!(name: "Grid Owner", email: "grid-owner@example.com", admin: true)
CurrentScope::RoleAssignment.create!(subject: owner, role: CurrentScope::Role.find_by!(name: "Owner"))
member = CurrentScope::Role.find_by!(name: "Member")

s = ActionDispatch::Integration::Session.new(Rails.application)
s.post "/sessions", params: { user_id: owner.id }

dump = lambda do |label|
  s.get "/permissions/roles/#{member.id}/edit"
  doc = Nokogiri::HTML(s.response.body)
  headers = doc.css("table.cs-grid thead th").map { |h| h.text.strip }
  rows = doc.css("table.cs-grid tbody tr").map do |r|
    name = r.at_css("th")&.text&.strip
    cells = r.css("td").map { |td| td["class"].to_s.include?("cs-cell-blank") ? "·" : (td.at_css("input")&.attr("value") || "?") }
    [ name, cells ]
  end
  puts "== #{label} =="
  puts "columns: #{headers.inspect}"
  rows.each { |name, cells| puts "  %-15s %s" % [ name, cells.inspect ] }
  puts
end

dump.call("custom groups (workflow=[approve,show] overlapping read)")

CurrentScope.config.permission_grid_groups = {
  "read" => %w[index show], "create" => %w[new create],
  "update" => %w[edit update], "destroy" => %w[destroy]
}
dump.call("default CRUD groups (approve becomes a leftover column)")
