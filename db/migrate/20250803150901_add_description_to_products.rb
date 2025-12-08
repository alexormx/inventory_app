# frozen_string_literal: true

class AddDescriptionToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :description, :text
  end
end
