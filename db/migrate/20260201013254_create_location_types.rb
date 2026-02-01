class CreateLocationTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :location_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :icon, default: 'bi-geo-alt'
      t.string :color, default: 'secondary'
      t.integer :position, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :location_types, :code, unique: true
    add_index :location_types, :position
    add_index :location_types, :active
  end
end
