class Report < ApplicationRecord
  include CurrentScope::Scopeable

  belongs_to :requested_by, class_name: "User"

  # SoD hook (probe 9): whoever requested the report can never approve it.
  def current_scope_initiator = requested_by

  def current_scope_label = "#{title} (##{id})"
end
