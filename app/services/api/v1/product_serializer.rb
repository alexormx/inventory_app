# frozen_string_literal: true

module Api
  module V1
    # Representación pública de un producto para integraciones (KataFrame).
    # Lista BLANCA: nunca agregar product_sku, supplier_product_code, costos,
    # utilidades ni proveedores — los identificadores de proveedor no salen.
    class ProductSerializer
      def initialize(product, url_builder:, stock_available:)
        @product = product
        @url_builder = url_builder
        @stock_available = stock_available
      end

      def as_json(*)
        p = @product
        {
          id: p.id,
          code: p.whatsapp_code,
          product_name: p.product_name,
          brand: p.brand,
          category: p.category,
          series: p.series,
          scale: p.scale,
          selling_price: p.selling_price,
          description: p.description,
          status: p.status,
          barcode: p.barcode,
          launch_date: p.launch_date,
          stock_available: @stock_available,
          length_cm: p.length_cm,
          width_cm: p.width_cm,
          height_cm: p.height_cm,
          weight_gr: p.weight_gr,
          custom_attributes: custom_attributes,
          image_urls: image_urls,
          updated_at: p.updated_at
        }
      end

      # Piezas que el cliente puede comprar ahora, por producto, en una consulta.
      def self.stock_by_product(product_ids)
        Inventory.customer_available_now.where(product_id: product_ids).group(:product_id).count
      end

      private

      def custom_attributes
        value = @product.custom_attributes
        value = JSON.parse(value) if value.is_a?(String)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end

      # Originales (no variantes): KataFrame los reutiliza en otras tiendas y
      # un listado completo no debe disparar ImageMagick en el dyno web.
      def image_urls
        @product.ordered_product_images.map { |attachment| @url_builder.rails_storage_proxy_url(attachment) }
      end
    end
  end
end
