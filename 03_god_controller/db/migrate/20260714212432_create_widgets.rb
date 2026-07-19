class CreateWidgets < ActiveRecord::Migration[8.1]
  def change
    create_table :widgets do |t|
      t.string :name

      t.timestamps
    end
  end
end
