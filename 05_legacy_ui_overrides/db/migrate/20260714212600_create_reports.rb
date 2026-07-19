class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.string :title
      t.string :state

      t.timestamps
    end
  end
end
