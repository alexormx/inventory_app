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

    # Selecciona por FIFO y BLOQUEA las filas de una línea (producto+cantidad),
    # sin escribir todavía. Se separa del guardado para que un lote pueda
    # validar TODAS sus líneas antes de tocar nada: si la tercera no alcanza,
    # las dos primeras nunca llegaron a escribirse.
    #
    # NO abre transacción: quien llama debe estar dentro de una.
    def lock_fifo_rows!(product_id, quantity)
      fifo_scope(product_id).lock.limit(quantity).to_a
    end

    # Aplica la ubicación a una pieza ya bloqueada y deja su rastro de auditoría.
    # Se guarda con save! (no update_all) para que corran los callbacks que
    # mantienen estadísticas y publicabilidad del producto. El estado NO se toca:
    # una pieza apartada sigue apartada, sólo pasa a tener ubicación.
    def assign_located!(inventory, location, actor:, source:, notes: nil, batch_id: nil)
      previous_status = inventory.status
      previous_location_id = inventory.inventory_location_id
      previous_sale_order_id = inventory.sale_order_id
      observed_updated_at = inventory.updated_at

      inventory.inventory_location = location
      inventory.save!

      metadata = {
        'result' => 'found',
        'notes' => notes,
        'actor_id' => actor.id,
        'actor_email' => actor.email,
        'actor_name' => actor.name,
        'previous_status' => previous_status,
        'new_status' => inventory.status,
        'previous_location_id' => previous_location_id,
        'new_location_id' => inventory.inventory_location_id,
        'product_id' => inventory.product_id,
        'purchase_order_id' => inventory.purchase_order_id,
        'purchase_order_item_id' => inventory.purchase_order_item_id,
        'sale_order_id' => inventory.sale_order_id,
        'sale_order_item_id' => inventory.sale_order_item_id,
        # En el flujo por cantidad no hay snapshot que el usuario haya visto: lo
        # verificado es el estado leído bajo bloqueo.
        'expected_updated_at' => observed_updated_at&.utc&.iso8601(6),
        'verified_inventory_updated_at' => inventory.updated_at.utc.iso8601(6),
        'assignment_source' => source
      }
      metadata['assignment_batch_id'] = batch_id if batch_id.present?

      InventoryEvent.create!(
        inventory: inventory,
        product_id: inventory.product_id,
        event_type: 'physical_inventory_verification',
        previous_sale_order_id: previous_sale_order_id,
        new_sale_order_id: inventory.sale_order_id,
        metadata: metadata
      )
    end
  end
end
