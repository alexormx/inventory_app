# frozen_string_literal: true

module PurchaseOrders
  class ReceptionProductResolverService
    Resolution = Struct.new(
      :supplier_product_code,
      :product_match,
      :name_similarity,
      :catalog_matches,
      :name_candidates,
      keyword_init: true
    )

    NAME_FUZZY_LIMIT = 5

    def initialize(supplier_product_code, product_name: nil, barcode: nil)
      @supplier_product_code = supplier_product_code.to_s.strip
      @product_name = product_name.to_s.strip
      @barcode = barcode.to_s.strip
    end

    def call
      Resolution.new(
        supplier_product_code: @supplier_product_code,
        product_match: product_match,
        name_similarity: product_match ? similarity(product_match.product_name) : nil,
        catalog_matches: catalog_matches,
        name_candidates: name_candidates
      )
    end

    private

    def product_match
      return @product_match if defined?(@product_match)

      @product_match = nil
      if @supplier_product_code.present?
        @product_match ||= Product.find_by(supplier_product_code: @supplier_product_code)
      end
      if @product_match.nil? && @barcode.present?
        @product_match ||= Product.find_by(barcode: @barcode)
      end
      @product_match
    end

    def catalog_matches
      return [] if @supplier_product_code.blank? && @barcode.blank?

      scope = SupplierCatalogItem.all
      conditions = []
      values = []
      if @supplier_product_code.present?
        conditions << "supplier_product_code = ?"
        values << @supplier_product_code
        conditions << "external_sku = ?"
        values << @supplier_product_code
      end
      if @barcode.present?
        conditions << "barcode = ?"
        values << @barcode
      end
      scope.where(conditions.join(" OR "), *values).limit(NAME_FUZZY_LIMIT).to_a
    end

    def name_candidates
      return [] if @product_name.blank? || product_match.present?

      keywords = extract_keywords(@product_name)
      return [] if keywords.empty?

      conditions = keywords.map { "LOWER(product_name) LIKE ?" }
      values = keywords.map { |kw| "%#{sanitize_like(kw.downcase)}%" }
      Product.where(conditions.join(" OR "), *values).limit(NAME_FUZZY_LIMIT).to_a
    end

    def similarity(other_name)
      return nil if @product_name.blank? || other_name.to_s.blank?

      ApplicationController.helpers.name_similarity_score(@product_name, other_name)
    end

    def extract_keywords(name)
      name.downcase.gsub(/[^a-z0-9\s]/, " ").split.select { |w| w.length >= 3 }.uniq.first(6)
    end

    def sanitize_like(string)
      string.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
