class Expense < ApplicationRecord
  belongs_to :requested_by, class_name: "User"

  def current_scope_initiator     = requested_by
  def current_scope_sod_bypassed? = sod_bypass_requested?
end
