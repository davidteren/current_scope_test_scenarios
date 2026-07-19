owner  = User.find_or_create_by!(email: "owner@example.com")  { |u| u.name = "Olivia Owner" }
member = User.find_or_create_by!(email: "member@example.com") { |u| u.name = "Marty Member" }
nobody = User.find_or_create_by!(email: "nobody@example.com") { |u| u.name = "Nadia NoRole" }

CurrentScope.seed_defaults!   # Owner (full_access) + Member roles
CurrentScope.grant!(owner)    # Owner role -> full access

Post.find_or_create_by!(title: "First post") { |p| p.body = "Hello world" }
Post.find_or_create_by!(title: "Second post") { |p| p.body = "More words" }

puts "Seeded: #{User.count} users, #{Post.count} posts, roles: #{CurrentScope::Role.pluck(:name).join(', ')}"
