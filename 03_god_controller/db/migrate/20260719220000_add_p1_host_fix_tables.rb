class AddP1HostFixTables < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :assigned, :boolean, default: false, null: false

    create_table :settings do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :settings, :key, unique: true

    create_table :report_deliveries do |t|
      t.string :kind, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
  end
end
