# frozen_string_literal: true

module Inventories
  # Reglas compartidas por los dos caminos que escriben una ubicación física:
  # la verificación unidad por unidad y la asignación por producto+cantidad.
  # Viven aquí para que "qué ubicación es válida" y "qué pieza puede ubicarse"
  # tengan una sola definición.
  module LocationAssignment
    class InvalidLocation < StandardError; end

    # Sólo se ubica lo que está físicamente en bodega. 'pre_reserved' queda
    # fuera a propósito: ReserveSaleOrderItem sólo la asigna cuando la pieza
    # está in_transit, así que todavía viene en camino y no hay nada que poner
    # en un estante.
    ELIGIBLE_STATUSES = %w[available reserved].freeze

    module_function

    # Una ubicación destino tiene que existir, estar activa y ser hoja: colgar
    # piezas de un nodo intermedio deja stock que nadie sabe dónde buscar.
    def validated_leaf_location!(location_id)
      raise InvalidLocation, 'Selecciona una ubicación física.' if location_id.blank?

      location = InventoryLocation.lock.find_by(id: location_id)
      raise InvalidLocation, 'La ubicación no existe.' unless location
      raise InvalidLocation, 'La ubicación está inactiva.' unless location.active?
      raise InvalidLocation, 'La ubicación debe ser final (sin sububicaciones).' unless location.leaf?

      location
    end

    # Inventario que hoy puede recibir ubicación para un producto.
    def eligible_scope(product_id)
      Inventory.where(product_id: product_id,
                      status: ELIGIBLE_STATUSES,
                      inventory_location_id: nil)
    end

    # FIFO: primero lo más viejo. created_at es la única fecha que todas las
    # piezas tienen (las compradas por PO y las capturadas a mano), y el id
    # desempata para que el orden sea estable entre corridas.
    def fifo_scope(product_id)
      eligible_scope(product_id).order(created_at: :asc, id: :asc)
    end
  end
end
