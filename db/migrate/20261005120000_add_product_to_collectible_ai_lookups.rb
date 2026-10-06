# frozen_string_literal: true

class AddProductToCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    add_reference :collectible_ai_lookups, :product, null: true, foreign_key: { on_delete: :nullify }
  end
end
