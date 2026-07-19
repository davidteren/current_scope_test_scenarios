class Report < ApplicationRecord
  include CurrentScope::Scopeable

  def current_scope_label = "#{title} (##{id})"
end
