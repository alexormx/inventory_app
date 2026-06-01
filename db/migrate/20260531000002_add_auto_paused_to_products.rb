# frozen_string_literal: true

# Distingue "pausado por el sistema" (sin stock publicable) de "inactivo por
# decisión del admin". Ambos casos siguen siendo status = 'inactive' (no se
# toca el enum), pero auto_paused marca cuáles los pausó la lógica de
# disponibilidad para que aparezcan en la cola de revisión y los reactive el
# admin uno a uno. auto_paused_at registra desde cuándo (para la cola).
class AddAutoPausedToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :auto_paused, :boolean, default: false, null: false
    add_column :products, :auto_paused_at, :datetime

    # Índice parcial: la cola de revisión y el job de reconciliación solo
    # consultan los pausados automáticamente (una fracción de la tabla).
    add_index :products, :auto_paused, where: 'auto_paused', name: 'index_products_on_auto_paused'
  end
end
