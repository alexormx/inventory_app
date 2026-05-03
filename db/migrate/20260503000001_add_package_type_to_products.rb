# frozen_string_literal: true

class AddPackageTypeToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :package_type, :string
    add_index  :products, :package_type
  end
end
