# frozen_string_literal: true

# Guías de la búsqueda con IA de coleccionables: en qué sitios identificar la
# pieza y de cuáles se aceptan precios (México y mundial). Se editan en el
# admin; mientras la tabla esté vacía se usan los sitios sugeridos de
# Collectibles::LookupSource::DEFAULTS.
class CreateCollectibleLookupSources < ActiveRecord::Migration[8.0]
  def change
    create_table :collectible_lookup_sources do |t|
      t.string :name, null: false
      t.string :domain, null: false
      t.integer :purpose, null: false, default: 0
      t.string :category
      t.string :search_url
      t.text :notes
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :collectible_lookup_sources, %i[purpose active]
  end
end
