# frozen_string_literal: true

class AddPurchaseDateToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :purchase_date, :date
    add_index  :inventories, :purchase_date
  end
end
