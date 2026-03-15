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
    end
  end
end
