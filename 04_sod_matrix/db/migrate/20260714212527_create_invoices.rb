class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.string :description
      t.integer :amount_cents
      t.references :requested_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
