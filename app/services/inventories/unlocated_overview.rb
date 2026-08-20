# frozen_string_literal: true

module Inventories
  # Lo que la pantalla de ubicar necesita saber sobre las piezas SIN ubicación:
  # los totales de arriba y las filas del buscador.
  #
  # Vive aparte del controlador porque la respuesta Turbo de "cambiar ubicación"
  # tiene que volver a pintar esas mismas filas —al elegir estante cambia el
  # estado de cada botón Agregar— y duplicar la consulta en dos controladores
  # era la forma segura de que se separaran con el tiempo.
  class UnlocatedOverview
    SEARCH_LIMIT = 25

    def initialize(term: nil)
      @term = term.to_s.strip
    end

    attr_reader :term

    # El listado sólo aparece cuando hay búsqueda: la pantalla es para ubicar lo
    # que traes en la mano, no para pasear por 800 productos.
    def rows
      @rows ||= term.present? ? search_rows : []
    end

    def total_assignable
      @total_assignable ||= counts.sum { |(_pid, status), n| assignable_status?(status) ? n : 0 }
    end

    def total_in_transit
      @total_in_transit ||= counts.sum { |(_pid, status), n| assignable_status?(status) ? 0 : n }
    end

    def total_products
      @total_products ||= counts.keys.map(&:first).uniq.size
    end

    private

    def counts
      @counts ||= Inventory.where(inventory_location_id: nil)
                           .where(status: Inventory::STATUSES_REQUIRING_LOCATION)
                           .group(:product_id, :status)
                           .count
    end

    def search_rows
      pattern = "%#{term.downcase}%"
      # Se precargan adjuntos y blobs: la lista muestra una miniatura por
      # producto y sin esto sería una consulta por fila.
      Product.where(id: counts.keys.map(&:first).uniq)
             .includes(product_images_attachments: :blob)
             .where('LOWER(product_name) LIKE :q OR LOWER(product_sku) LIKE :q', q: pattern)
             .order(:product_name)
             .limit(SEARCH_LIMIT)
             .map { |product| row_for(product) }
    end

    def row_for(product)
      per_status = counts.select { |(pid, _status), _n| pid == product.id }
                         .transform_keys { |(_pid, status)| status.to_s }
      {
        product: product,
        available: per_status['available'].to_i,
        reserved: per_status['reserved'].to_i,
        in_transit: per_status['pre_reserved'].to_i,
        assignable: per_status.sum { |status, n| assignable_status?(status) ? n : 0 }
      }
    end

    # 'pre_reserved' requiere ubicación según el modelo, pero físicamente sigue
    # en tránsito: se muestra aparte y no entra en lo asignable.
    def assignable_status?(status)
      Inventories::LocationAssignment::ELIGIBLE_STATUSES.include?(status.to_s)
    end
  end
end
