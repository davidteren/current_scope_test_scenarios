CurrentScope.seed_defaults!

owner  = User.find_or_create_by!(email: "owner@example.com")  { |u| u.name = "Olive Owner";  u.api_token = "owner-token" }
member = User.find_or_create_by!(email: "member@example.com") { |u| u.name = "Manny Member"; u.api_token = "member-token" }
User.find_or_create_by!(email: "nobody@example.com") { |u| u.name = "Nadia Nobody"; u.api_token = "nobody-token" }

CurrentScope.grant!(owner) # full-access Owner role

member_role = CurrentScope::Role.find_by!(name: "Member")
member_role.role_permissions.find_or_create_by!(permission_key: "api/v1/items#index")
member_role.role_permissions.find_or_create_by!(permission_key: "items#index")
CurrentScope::RoleAssignment.find_or_create_by!(subject: member) { |a| a.role = member_role }

Item.find_or_create_by!(name: "Anvil")  { |i| i.user = owner }
Item.find_or_create_by!(name: "Bucket") { |i| i.user = member }
Item.find_or_create_by!(name: "Crate")  { |i| i.user = owner }
