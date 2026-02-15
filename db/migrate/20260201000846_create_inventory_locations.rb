# frozen_string_literal: true

class CreateInventoryLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_locations do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :location_type, null: false
      t.text :description
      t.references :parent, null: true, foreign_key: { to_table: :inventory_locations }
      t.integer :position, default: 0
      t.boolean :active, default: true, null: false
      t.integer :depth, default: 0, null: false # Cache depth level for queries
      t.string :path_cache # Cache full path like "Bodega A > Sección 1 > Estante A"

      t.timestamps
    end

    add_index :inventory_locations, :code, unique: true
    add_index :inventory_locations, :location_type
    add_index :inventory_locations, :active
    add_index :inventory_locations, %i[parent_id position]
  end
end
