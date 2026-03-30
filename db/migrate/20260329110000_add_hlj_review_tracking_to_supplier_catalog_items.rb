class AddHljReviewTrackingToSupplierCatalogItems < ActiveRecord::Migration[8.0]
  def change
    add_column :supplier_catalog_items, :last_hlj_recent_added_at, :datetime
    add_column :supplier_catalog_items, :last_hlj_recent_arrival_at, :datetime

    add_index :supplier_catalog_items, :last_hlj_recent_added_at
    add_index :supplier_catalog_items, :last_hlj_recent_arrival_at
  end
end