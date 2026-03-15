# frozen_string_literal: true

class CreateSupplierCatalogFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :supplier_catalog_items do |t|
      t.string :source_key, null: false, default: "hlj"
      t.string :external_sku, null: false
      t.string :barcode
      t.string :supplier_product_code
      t.references :product, null: true, foreign_key: true
      t.string :canonical_name, null: false
      t.string :canonical_brand
      t.string :canonical_category
      t.string :canonical_series
      t.string :canonical_item_type
      t.date :canonical_release_date
      t.decimal :canonical_price, precision: 10, scale: 2
      t.string :currency, null: false, default: "MXN"
      t.string :canonical_status
      t.string :source_url
      t.string :main_image_url
      t.text :image_urls, default: "[]", null: false
      t.text :description_raw
      t.text :details_payload, default: "{}", null: false
      t.text :raw_payload, default: "{}", null: false
      t.string :content_checksum
      t.boolean :needs_review, null: false, default: false
      t.datetime :last_seen_at
      t.datetime :last_status_change_at
      t.datetime :last_full_sync_at
      t.datetime :source_last_synced_at

      t.timestamps
    end

    add_index :supplier_catalog_items, [:source_key, :external_sku], unique: true, name: "idx_supplier_catalog_items_source_sku"
    add_index :supplier_catalog_items, :barcode
    add_index :supplier_catalog_items, :canonical_status
    add_index :supplier_catalog_items, :last_seen_at

    create_table :supplier_catalog_sources do |t|
      t.references :supplier_catalog_item, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id
      t.string :source_url
      t.string :fetch_status, null: false, default: "pending"
      t.integer :last_http_status
      t.text :last_error_message
      t.text :image_urls, default: "[]", null: false
      t.text :normalized_payload, default: "{}", null: false
      t.text :raw_payload, default: "{}", null: false
      t.text :metadata, default: "{}", null: false
      t.string :content_checksum
      t.datetime :last_seen_at
      t.datetime :last_changed_at

      t.timestamps
    end

    add_index :supplier_catalog_sources, [:supplier_catalog_item_id, :source], unique: true, name: "idx_supplier_catalog_sources_item_source"
    add_index :supplier_catalog_sources, :external_id
    add_index :supplier_catalog_sources, :last_seen_at

    create_table :supplier_sync_runs do |t|
      t.string :source, null: false
      t.string :mode, null: false
      t.string :status, null: false, default: "queued"
      t.references :supplier_catalog_item, null: true, foreign_key: true
      t.integer :processed_count, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :metadata, default: "{}", null: false
      t.text :error_samples, default: "[]", null: false

      t.timestamps
    end

    add_index :supplier_sync_runs, [:source, :mode, :created_at], name: "idx_supplier_sync_runs_source_mode_created"
    add_index :supplier_sync_runs, :status
  end
end