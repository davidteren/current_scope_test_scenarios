class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :number
      t.string :status
      t.boolean :archived

      t.timestamps
    end
  end
end
