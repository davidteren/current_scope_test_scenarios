alice = User.find_or_create_by!(email: "alice@example.com") { |u| u.name = "Alice (admin)" }
bob   = User.find_or_create_by!(email: "bob@example.com")   { |u| u.name = "Bob (approver)" }
carol = User.find_or_create_by!(email: "carol@example.com") { |u| u.name = "Carol (requester)" }

CurrentScope.seed_defaults!            # Owner (full_access) + Member
CurrentScope.grant!(alice)             # Owner

approver = CurrentScope::Role.find_or_create_by!(name: "Approver")
approver.update!(permission_keys: %w[expenses#index expenses#show expenses#approve expenses#reject expenses#approve_all])
CurrentScope::RoleAssignment.find_or_create_by!(subject: bob) { |a| a.role = approver }

Expense.find_or_create_by!(description: "Team lunch", requested_by: carol) { |e| e.amount_cents = 4500 }
Expense.find_or_create_by!(description: "Alice's conference", requested_by: alice) { |e| e.amount_cents = 120_000 }
Invoice.find_or_create_by!(description: "Vendor invoice", requested_by: carol) { |i| i.amount_cents = 99_000 }
