class CreateProductCatalogReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :product_catalog_reviews do |t|
      t.references :product, null: false, foreign_key: true, index: { unique: true }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :review_mode
      t.text :notes
      t.datetime :reviewed_at, null: false

      t.timestamps
    end
  end
end
