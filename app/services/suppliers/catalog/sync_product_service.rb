# frozen_string_literal: true

module Suppliers
  module Catalog
    class SyncProductService
      Result = Struct.new(:product, :created, :linked, keyword_init: true)

      def initialize(catalog_item, product: nil, force_full_update: false)
        @catalog_item = catalog_item
        @product = product || catalog_item.product
        @force_full_update = force_full_update
      end

      def call
        created = false

        ActiveRecord::Base.transaction do
          @product ||= find_existing_product
          @product ||= Product.new
          created = @product.new_record?

          assign_product_attributes(created: created)
          @product.save!

          @catalog_item.update!(product: @product, needs_review: false)
        end

        Result.new(product: @product, created: created, linked: @catalog_item.reload.product_id.present?)
      end

      private

      def find_existing_product
        if @catalog_item.barcode.present?
          product = Product.find_by(barcode: @catalog_item.barcode)
          return product if product
        end

        if @catalog_item.external_sku.present?
          product = Product.find_by(product_sku: @catalog_item.external_sku)
          return product if product
        end

        if @catalog_item.supplier_product_code.present?
          product = Product.find_by(supplier_product_code: @catalog_item.supplier_product_code)
          return product if product
        end

        nil
      end

      def assign_product_attributes(created:)
        @product.product_sku = @catalog_item.external_sku if created || @product.product_sku.blank?
        @product.product_name = @catalog_item.canonical_name if created || @force_full_update || @product.product_name.blank?
        @product.brand = @catalog_item.canonical_brand.presence || @product.brand.presence || "HLJ"
        @product.category = @catalog_item.canonical_category.presence || @product.category.presence || "diecast"
        @product.status = "draft" if created && @product.status.blank?

        sync_safe_fields(created: created)
        sync_supplier_attributes
      end

      def sync_safe_fields(created:)
        @product.barcode = @catalog_item.barcode if @catalog_item.barcode.present?
        @product.supplier_product_code = @catalog_item.supplier_product_code if @catalog_item.supplier_product_code.present?
        @product.series = @catalog_item.canonical_series if @catalog_item.canonical_series.present? && (created || @force_full_update || @product.series.blank?)
        @product.launch_date = @catalog_item.canonical_release_date if @catalog_item.canonical_release_date.present? && (created || @force_full_update || @product.launch_date.blank?)

        if @catalog_item.canonical_price.present? && (created || @force_full_update || @product.selling_price.blank? || @product.selling_price.to_f <= 0)
          @product.selling_price = @catalog_item.canonical_price
        end

        @product.minimum_price = @product.selling_price if created || @product.minimum_price.blank? || @product.minimum_price.to_f <= 0
        @product.maximum_discount = 0 if @product.maximum_discount.blank?
        @product.reorder_point = 0 if @product.reorder_point.blank?

        if @catalog_item.description_raw.present? && (@product.description_missing? || @force_full_update)
          @product.description = @catalog_item.description_raw
        end
      end

      def sync_supplier_attributes
        attrs = @product.parsed_custom_attributes.deep_dup
        attrs["supplier_catalog"] = {
          "source_key" => @catalog_item.source_key,
          "external_sku" => @catalog_item.external_sku,
          "barcode" => @catalog_item.barcode,
          "supplier_product_code" => @catalog_item.supplier_product_code,
          "status" => @catalog_item.canonical_status,
          "series" => @catalog_item.canonical_series,
          "item_type" => @catalog_item.canonical_item_type,
          "source_url" => @catalog_item.source_url,
          "main_image_url" => @catalog_item.main_image_url,
          "image_urls" => Array(@catalog_item.image_urls)
        }.compact

        @product.custom_attributes = attrs
      end
    end
  end
end