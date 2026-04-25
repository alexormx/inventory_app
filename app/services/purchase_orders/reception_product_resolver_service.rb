# frozen_string_literal: true

module PurchaseOrders
  class ReceptionProductResolverService
    Resolution = Struct.new(:product, :catalog_item, :source, keyword_init: true)

    def initialize(supplier_product_code, hlj_lookup: nil)
      @supplier_product_code = supplier_product_code.to_s.strip
      @hlj_lookup = hlj_lookup || method(:lookup_hlj_catalog_item)
    end

    def call
      return if @supplier_product_code.blank?

      product = Product.find_by(supplier_product_code: @supplier_product_code)
      return Resolution.new(product: product, source: :product) if product

      catalog_item = SupplierCatalogItem.find_by(supplier_product_code: @supplier_product_code)
      if catalog_item
        synced = Suppliers::Catalog::SyncProductService.new(catalog_item).call
        return Resolution.new(product: synced.product, catalog_item: catalog_item, source: :catalog)
      end

      catalog_item = @hlj_lookup.call(@supplier_product_code)
      return unless catalog_item

      synced = Suppliers::Catalog::SyncProductService.new(catalog_item).call
      Resolution.new(product: synced.product, catalog_item: catalog_item, source: :hlj)
    end

    private

    def lookup_hlj_catalog_item(code)
      Suppliers::Hlj::ImportBySupplierCodeService.new(code).call
    end
  end
end