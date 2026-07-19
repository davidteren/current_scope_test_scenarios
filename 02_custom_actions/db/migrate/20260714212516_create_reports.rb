class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.string :title
      t.string :state, default: "draft"
      t.references :requested_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
