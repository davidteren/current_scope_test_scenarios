# This migration comes from current_scope (originally 20260714000001)
class AddDescriptionToCurrentScopeRoles < ActiveRecord::Migration[7.1]
  def change
    add_column :current_scope_roles, :description, :text
  end
end
