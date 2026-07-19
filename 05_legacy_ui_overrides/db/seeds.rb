CurrentScope.seed_defaults!

owner  = User.find_or_create_by!(email: "owner@example.com")  { |u| u.name = "Olive Owner";  u.admin = true }
staff  = User.find_or_create_by!(email: "staff@example.com")  { |u| u.name = "Sam Staff";    u.admin = false }
admin  = User.find_or_create_by!(email: "admin@example.com")  { |u| u.name = "Ada Admin";    u.admin = true }
User.where(email: nil).first_or_create!(name: "No Email", admin: false)

CurrentScope.grant!(owner) # full-access Owner

member = CurrentScope::Role.find_by!(name: "Member")
member.update!(permission_keys: %w[
  dashboard#show reports#index reports#show
])
CurrentScope::RoleAssignment.find_or_create_by!(subject: staff, role: member)

reviewer = CurrentScope::Role.find_or_create_by!(name: "Reviewer")
reviewer.update!(permission_keys: %w[
  dashboard#show reports#index reports#show
  admin/reports#index admin/reports#show admin/reports#approve
])
CurrentScope::RoleAssignment.find_or_create_by!(subject: admin, role: reviewer)

Report.find_or_create_by!(title: "Q1 numbers") { |r| r.state = "pending" }
Report.find_or_create_by!(title: "Q2 numbers") { |r| r.state = "pending" }
Project.find_or_create_by!(name: "Apollo")
