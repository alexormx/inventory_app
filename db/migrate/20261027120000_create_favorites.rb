# frozen_string_literal: true

# Lista de deseos del cliente. Un favorito no se borra al quitarlo o al
# comprarlo: se cierra con removed_at y su motivo, para que las estadísticas
# de "lo guardó y luego lo compró" sobrevivan. Sólo puede haber un favorito
# abierto por cliente y producto.
class CreateFavorites < ActiveRecord::Migration[8.0]
  def change
    create_table :favorites do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.string :source, null: false, default: 'heart'
      t.datetime :removed_at
      t.string :removal_reason
      t.string :sale_order_id
      t.timestamps
    end

    add_index :favorites, %i[user_id product_id], unique: true, where: 'removed_at IS NULL',
                                                  name: 'index_favorites_open_per_user_product'
    add_index :favorites, %i[product_id removed_at]
  end
end
