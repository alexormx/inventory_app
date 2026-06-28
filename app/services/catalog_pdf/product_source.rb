require 'base64'

module CatalogPdf
  # Construye la lista de ítems del catálogo a partir de productos reales.
  # Ordena por serie y luego nombre y solo incluye productos con ubicación
  # física confirmada.
  module ProductSource
    module_function

    # Ítems con la imagen embebida como data URI (para generar el PDF en local
    # contra la BD local). El generador remoto usa `payload` + RemoteSource.
    def items(scope: Product.with_confirmed_location)
      ordered(scope).map { |product| base_fields(product).merge(image: image_data_uri(product)) }
    end

    # Recorre el payload del API producto por producto, en lotes, sin
    # materializar todos los registros ni todo el arreglo en memoria. El
    # controlador hace stream del JSON conforme se generan los ítems, así el
    # pico de RSS por petición queda acotado (clave en el dyno Basic de 512 MB).
    # Generar la URL de imagen es barato (Active Storage no procesa la variante
    # hasta que alguien la descarga). `url_builder` responde a
    # `rails_storage_proxy_url`.
    def each_payload(url_builder:, scope: Product.with_confirmed_location, batch_size: 250)
      scope.with_attached_product_images.find_each(batch_size: batch_size) do |product|
        yield base_fields(product).merge(image_url: image_url(product, url_builder))
      end
    end

    def ordered(scope)
      scope.order(:series, :product_name).with_attached_product_images
    end

    def base_fields(product)
      {
        code: product.whatsapp_code,
        name: product.product_name,
        brand: product.brand,
        series: product.series.presence || 'Sin serie',
        scale: (product.show_scale_publicly? ? product.scale.presence : nil),
        price: product.selling_price,
        badges: badges_for(product)
      }
    end

    def badges_for(product)
      badges = []
      badges << 'Nuevo' if product.created_at && product.created_at >= 1.month.ago
      badges << 'Única Pieza' if on_hand(product) == 1
      badges
    end

    def on_hand(product)
      product.current_on_hand
    rescue StandardError
      0
    end

    # URL (proxy, firmada y pública) de la variante 600x600. No procesa la
    # imagen aquí; la descarga (y el procesamiento perezoso) ocurren cuando el
    # generador local la baja, repartiendo la carga en peticiones pequeñas.
    def image_url(product, url_builder)
      attachment = product.primary_product_image
      return nil if attachment.blank?

      url_builder.rails_storage_proxy_url(attachment.variant(resize_to_limit: [600, 600]))
    rescue StandardError
      nil
    end

    # Imagen embebida como data URI (base64). Embeber evita depender de un
    # servidor corriendo y funciona igual con S3 o disco local.
    def image_data_uri(product)
      attachment = product.primary_product_image
      return nil if attachment.blank?

      blob = attachment.blob
      data =
        begin
          attachment.variant(resize_to_limit: [600, 600]).processed.download
        rescue StandardError
          attachment.download
        end
      "data:#{blob.content_type};base64,#{Base64.strict_encode64(data)}"
    rescue StandardError
      nil
    end
  end
end
