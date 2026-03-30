class CreateSupplierCatalogReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :supplier_catalog_reviews do |t|
      t.references :supplier_catalog_item, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :review_mode, null: false
      t.text :notes
      t.datetime :reviewed_at, null: false

      t.timestamps
    end

    add_index :supplier_catalog_reviews,
              [:supplier_catalog_item_id, :review_mode],
              unique: true,
              name: "idx_supplier_catalog_reviews_item_mode"
  end
end