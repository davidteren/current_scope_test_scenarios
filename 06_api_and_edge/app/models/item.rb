class Item < ApplicationRecord
  include CurrentScope::Scopeable

  belongs_to :user, optional: true

  def current_scope_label = "#{name} (##{id})"
end
