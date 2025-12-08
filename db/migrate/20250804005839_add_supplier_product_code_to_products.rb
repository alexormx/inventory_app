# frozen_string_literal: true

class AddSupplierProductCodeToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :supplier_product_code, :string
  end
end
