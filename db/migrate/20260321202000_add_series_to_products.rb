# frozen_string_literal: true

class AddSeriesToProducts < ActiveRecord::Migration[8.0]
  class MigrationProduct < ApplicationRecord
    self.table_name = "products"

    has_one :supplier_catalog_item,
            class_name: "AddSeriesToProducts::MigrationSupplierCatalogItem",
            foreign_key: :product_id,
            inverse_of: :product
  end

  class MigrationSupplierCatalogItem < ApplicationRecord
    self.table_name = "supplier_catalog_items"

    belongs_to :product,
               class_name: "AddSeriesToProducts::MigrationProduct",
               optional: true,
               inverse_of: :supplier_catalog_item
  end

  def up
    add_column :products, :series, :string
    add_index :products, :series

    MigrationProduct.reset_column_information

    say_with_time "Backfilling products.series" do
      MigrationProduct.includes(:supplier_catalog_item).find_each do |product|
        series = product.supplier_catalog_item&.canonical_series.presence || extract_series_from_custom_attributes(product.custom_attributes)
        next if series.blank?

        product.update_columns(series: series)
      end
    end
  end

  def down
    remove_index :products, :series
    remove_column :products, :series
  end

  private

  def extract_series_from_custom_attributes(raw_attributes)
    attributes = case raw_attributes
                 when Hash
                   raw_attributes
                 when String
                   JSON.parse(raw_attributes)
                 else
                   {}
                 end

    attributes["series"].presence || attributes["serie"].presence
  rescue JSON::ParserError
    nil
  end
end