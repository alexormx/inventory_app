class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :product_sku, null: false
      t.string :barcode
      t.string :product_name, null: false
      t.string :brand, null: false
      t.string :category, null: false
      t.references :supplier, null: false, foreign_key: { to_table: :users }
      t.integer :stock_quantity, null: false, default: 0
      t.integer :reserved_quantity, null: false, default: 0
      t.integer :reorder_point, null: false, default: 0
      t.decimal :selling_price, precision: 10, scale: 2, null: false
      t.decimal :maximum_discount, precision: 10, scale: 2, null: false
      t.integer :discount_limited_stock, null: false, default: 0
      t.decimal :minimum_price, precision: 10, scale: 2, null: false
      t.boolean :backorder_allowed, default: false
      t.boolean :preorder_available, default: false
      t.string :status, null: false, default: "Active"
      t.text :product_images
      if ActiveRecord::Base.connection.adapter_name.downcase.starts_with?("sqlite")
        t.text :custom_attributes
      else
        t.jsonb :custom_attributes, default: {}
      end

      t.timestamps
    end
    # ✅ Ensure product_sku is unique
    add_index :products, :product_sku, unique: true
  
  end
end
