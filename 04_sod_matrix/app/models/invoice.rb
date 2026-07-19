# Deliberately NO current_scope_initiator hook — scenario 3 probes the
# loud-not-open ConfigurationError when an SoD action reaches it.
class Invoice < ApplicationRecord
  belongs_to :requested_by, class_name: "User"
end
