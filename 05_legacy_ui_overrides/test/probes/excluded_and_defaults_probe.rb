# Run with: RAILS_ENV=test bin/rails runner test/probes/excluded_and_defaults_probe.rb
# Probe 7: excluded_controllers vs a still-Guard'd namespace, then exclude+skip.
# Also: the OUT-OF-THE-BOX denial response (no host rescue_from), and
# rescue_responses registration for AccessDenied.
require "action_dispatch/testing/integration"

CurrentScope.seed_defaults!
owner_role = CurrentScope::Role.find_by!(name: "Owner")
owner   = User.create!(name: "Probe Owner",   email: "probe-owner@example.com",   admin: true)
nogrant = User.create!(name: "Probe NoGrant", email: "probe-nogrant@example.com", admin: true)
CurrentScope::RoleAssignment.create!(subject: owner, role: owner_role)
report = Report.create!(title: "probe", state: "pending")

s = ActionDispatch::Integration::Session.new(Rails.application)
s.post "/sessions", params: { user_id: owner.id }
s.get "/admin/reports"
puts "[baseline] owner GET /admin/reports -> #{s.response.status}"

puts
puts "== A: excluded_controllers += [/\\Aadmin\\//] while Admin::* still includes Guard =="
CurrentScope.config.excluded_controllers += [ /\Aadmin\// ]
CurrentScope.reset_catalog!
begin
  s.get "/admin/reports"
  puts "[excluded, still gated] -> HTTP #{s.response.status}"
rescue => e
  puts "[excluded, still gated] RAISED #{e.class}"
  puts "  message: #{e.message}"
end

puts
puts "== B: exclude + skip_before_action :current_scope_check! =="
Admin::BaseController.skip_before_action :current_scope_check!
s2 = ActionDispatch::Integration::Session.new(Rails.application)
s2.post "/sessions", params: { user_id: nogrant.id }
s2.get "/admin/reports"
puts "[no-grant host-admin] GET /admin/reports -> #{s2.response.status}#{' — UNGATED' if s2.response.status == 200}"
s2.post "/admin/reports/#{report.id}/approve"
puts "[no-grant host-admin] POST approve -> #{s2.response.status}; report.state=#{report.reload.state}"

member = CurrentScope::Role.find_by!(name: "Member")
s.get "/permissions/roles/#{member.id}/edit"
puts "[grid] edit page still lists 'admin/reports'? #{s.response.body.include?("admin/reports")}"

puts
puts "== C: out-of-the-box denial (no host rescue_from — MutationGuard's default) =="
# Re-register the engine's own handler AFTER the host's branded one, restoring
# the precedence a README-following host (which never adds rescue_from) has.
ApplicationController.rescue_from(CurrentScope::AccessDenied, with: :current_scope_denied)
s3 = ActionDispatch::Integration::Session.new(Rails.application)
s3.post "/sessions", params: { user_id: nogrant.id }
s3.get "/dashboard"
puts "[default denial] GET /dashboard -> HTTP #{s3.response.status}"
puts "[default denial] body: #{s3.response.body.inspect} (#{s3.response.body.bytesize} bytes)"
puts "[default denial] X-Current-Scope-Reason: #{s3.response.headers["X-Current-Scope-Reason"].inspect}"

puts
puts "== D: rescue_responses registration =="
status = ActionDispatch::ExceptionWrapper.rescue_responses["CurrentScope::AccessDenied"]
puts "ActionDispatch rescue_responses['CurrentScope::AccessDenied'] = #{status.inspect} (what an ESCAPED raise becomes in production)"
