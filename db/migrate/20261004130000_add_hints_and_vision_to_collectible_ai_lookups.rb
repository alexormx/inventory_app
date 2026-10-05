# frozen_string_literal: true

class AddHintsAndVisionToCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    add_column :collectible_ai_lookups, :hints, :text
    add_column :collectible_ai_lookups, :vision_used, :boolean, null: false, default: false
  end
end
