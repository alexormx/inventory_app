# frozen_string_literal: true

class AddPhotoRolesToCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    add_column :collectible_ai_lookups, :photo_roles, :string, array: true, default: [], null: false
  end
end
