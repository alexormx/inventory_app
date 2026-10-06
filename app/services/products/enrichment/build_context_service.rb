# frozen_string_literal: true

module Products
  module Enrichment
    # Builds a context hash from a Product, used as input for prompt construction.
    # Extracts all relevant product data + category attribute template.
    class BuildContextService
      def initialize(product)
        @product = product
      end

      def call
        {
          product_id:        @product.id,
          product_sku:       @product.product_sku,
          product_name:      @product.product_name,
          brand:             @product.brand,
          category:          @product.category,
          description:       @product.description,
          selling_price:     @product.selling_price.to_f,
          custom_attributes: @product.parsed_custom_attributes,
          dimensions:        build_dimensions,
          barcode:           @product.barcode,
          supplier_code:     @product.supplier_product_code,
          launch_date:       @product.launch_date&.iso8601,
          discontinued:      @product.discontinued?,
          supplier_context:  build_supplier_context,
          ai_lookup:         build_ai_lookup_context,
          template:          build_template_context
        }
      end

      private

      def build_dimensions
        {
          weight_gr: @product.weight_gr.to_f,
          length_cm: @product.length_cm.to_f,
          width_cm:  @product.width_cm.to_f,
          height_cm: @product.height_cm.to_f
        }
      end

      def build_template_context
        template = @product.attribute_template
        return nil unless template

        {
          category:    template.category,
          schema:      template.attributes_schema,
          keys:        template.attribute_keys,
          required:    template.required_keys
        }
      end

      # La identificación de quick_add ligada a este producto (la más reciente
      # que terminó). Sólo identificación, lanzamiento y rareza: los precios y
      # las URLs no le sirven a la descripción.
      def build_ai_lookup_context
        result = @product.collectible_ai_lookups.done.order(created_at: :desc).first&.result
        return nil unless result.is_a?(Hash)

        identification = result['identification'].is_a?(Hash) ? result['identification'] : {}
        {
          identification: identification.slice(*%w[product_name brand series model_code scale year_or_edition]).compact_blank,
          launch_date: result.dig('launch_date', 'value'),
          rarity_level: result.dig('rarity', 'level'),
          rarity_reasons: Array(result.dig('rarity', 'reasons'))
        }
      end

      def build_supplier_context
        Suppliers::Catalog::SupplierContextService.new(@product).call
      end
    end
  end
end
