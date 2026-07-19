class CreateExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :expenses do |t|
      t.string :description
      t.integer :amount_cents
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.boolean :sod_bypass_requested, default: false, null: false

      t.timestamps
    end
  end
end
