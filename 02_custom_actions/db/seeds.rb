alice = User.find_or_create_by!(email: "alice@example.com") { |u| u.name = "Alice Owner" }
bob   = User.find_or_create_by!(email: "bob@example.com")   { |u| u.name = "Bob Member" }
carol = User.find_or_create_by!(email: "carol@example.com") { |u| u.name = "Carol NoRole" }

CurrentScope.seed_defaults!          # Owner (full_access) + Member
CurrentScope.grant!(alice)           # Alice = Owner
CurrentScope.grant!(bob, role: CurrentScope::Role.find_by!(name: "Member"))

Report.find_or_create_by!(title: "Q1 Budget")  { |r| r.requested_by = alice }
Report.find_or_create_by!(title: "Q2 Budget")  { |r| r.requested_by = bob }
Report.find_or_create_by!(title: "Audit 2026") { |r| r.requested_by = carol }
