alice = User.find_or_create_by!(name: "Alice", email: "alice@example.com") # will become Owner
bob   = User.find_or_create_by!(name: "Bob",   email: "bob@example.com")   # partial role
carol = User.find_or_create_by!(name: "Carol", email: "carol@example.com") # no roles

Customer.find_or_create_by!(name: "Acme")   { |c| c.active = true; c.assigned = false }
Customer.find_or_create_by!(name: "Globex") { |c| c.active = false; c.assigned = false }
Order.find_or_create_by!(number: "ORD-1") { |o| o.status = "pending"; o.archived = false }
Order.find_or_create_by!(number: "ORD-2") { |o| o.status = "approved"; o.archived = true }
Widget.find_or_create_by!(name: "Sprocket")
Widget.find_or_create_by!(name: "Cog")

CurrentScope.seed_defaults!
CurrentScope.grant!(alice)   # Alice = Owner (full_access)
