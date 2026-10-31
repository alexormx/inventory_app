# frozen_string_literal: true

module Api
  module V1
    # Representación pública de un producto para integraciones (KataFrame).
    # Lista BLANCA: nunca agregar product_sku, supplier_product_code, costos,
    # utilidades ni proveedores — los identificadores de proveedor no salen.
    class ProductSerializer
      # Estatus de piezas que ya salieron de la tienda: no suman al `total`.
      GONE_STATUSES = %w[sold pre_sold lost scrap].freeze

      def initialize(product, url_builder:, stock_available:, inventory: {}, publishable: false)
        @product = product
        @url_builder = url_builder
        @stock_available = stock_available
        @inventory = inventory
        @publishable = publishable
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
          publishable: @publishable,
          inventory: inventory,
          badge: badge,
          tags: tags,
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

      # Los que cumplen la regla del admin para publicar (Product#eligible_for_publication?).
      def self.publishable_ids(product_ids)
        Product.eligible_for_publication.where(id: product_ids).pluck(:id).to_set
      end

      # Piezas por estatus, por producto, en una consulta: { id => { 'available' => 2, ... } }.
      def self.inventory_by_product(product_ids)
        Inventory.where(product_id: product_ids).group(:product_id, :status).count
                 .each_with_object(Hash.new { |h, k| h[k] = {} }) do |((product_id, status), count), acc|
          acc[product_id][status.to_s] = count
        end
      end

      private

      # Todos los estatus siempre presentes (0 si no hay piezas), más `total`:
      # lo que la tienda tiene o está por recibir (sin vendidas, perdidas ni merma).
      def inventory
        counts = Inventory.statuses.keys.index_with { |status| @inventory.fetch(status, 0) }
        { total: counts.except(*GONE_STATUSES).values.sum, **counts.symbolize_keys }
      end

      # La misma insignia que muestra la tienda ("Recién llegado", ...) o nil.
      def badge
        type = @product.catalog_event
        type && ProductsHelper::CATALOG_EVENT_PRESENTATION.dig(type, :label)
      end

      def tags
        Array(@product.seo_keywords).filter_map { |keyword| keyword.to_s.strip.presence }
      end

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
