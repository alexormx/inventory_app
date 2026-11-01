# frozen_string_literal: true

module SaleOrders
  # Borra un pedido EN BLANCO: hoy no tiene productos ni piezas de inventario,
  # no se recibió dinero, no se despachó y no tiene preventas activas.
  #
  # Lo que solo es rastro del pedido no lo bloquea:
  # - se borran: pagos sin cobrar, envío no despachado, snapshot de dirección,
  #   líneas canceladas y el carrito de la tienda que se convirtió en él;
  # - se desligan (quedan sin pedido): solicitud de WhatsApp, favoritos,
  #   preventas canceladas y bitácora de asignación de inventario;
  # - se conservan intactos: los InventoryEvent (historial de cada pieza).
  #
  # Un pedido con contenido se sigue manejando con Cancelar.
  class DestroyBlankOrder
    # Confirmed incluido: un pedido con total $0 se confirma solo (0 >= 0 en
    # fully_paid?), así quedan los pedidos en blanco creados desde el admin.
    DELETABLE_STATUSES = %w[Pending Confirmed Canceled].freeze
    RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze
    UNSHIPPED_SHIPMENT_STATUSES = %w[pending canceled].freeze

    Result = Struct.new(:destroyed, :reasons, keyword_init: true) do
      def success? = destroyed == true
    end

    def self.call(sale_order) = new(sale_order).call

    # Motivos por los que NO se puede borrar; vacío = se puede.
    def self.blocking_reasons(sale_order) = new(sale_order).blocking_reasons

    def initialize(sale_order)
      @sale_order = sale_order
    end

    def call
      SaleOrder.transaction do
        @sale_order.lock!
        reasons = blocking_reasons
        return Result.new(destroyed: false, reasons: reasons) if reasons.any?

        clean_up_traces!
        @sale_order.order_shipping_address&.destroy!
        @sale_order.reload.destroy!
      end
      Result.new(destroyed: true, reasons: [])
    end

    def blocking_reasons
      id = @sale_order.id
      reasons = []
      reasons << 'solo se pueden borrar pedidos pendientes, confirmados o cancelados' unless DELETABLE_STATUSES.include?(@sale_order.status)
      reasons << 'tiene productos' if @sale_order.sale_order_items.exists?
      reasons << 'tiene piezas de inventario asignadas' if Inventory.exists?(sale_order_id: id)
      reasons << 'tiene pagos recibidos o reembolsados' if Payment.exists?(sale_order_id: id, status: RECEIVED_PAYMENT_STATUSES)
      reasons << 'el envío ya se despachó' if Shipment.where(sale_order_id: id).where.not(status: UNSHIPPED_SHIPMENT_STATUSES).exists?
      reasons << 'tiene preventas activas' if PreorderReservation.where(sale_order_id: id).where.not(status: :cancelled).exists?
      reasons
    end

    private

    def clean_up_traces!
      id = @sale_order.id
      Payment.where(sale_order_id: id).delete_all
      Shipment.where(sale_order_id: id).delete_all
      CanceledOrderItem.where(sale_order_id: id).delete_all

      PreorderReservation.where(sale_order_id: id).update_all(sale_order_id: nil, updated_at: Time.current)
      WhatsappRequest.where(sale_order_id: id).update_all(sale_order_id: nil, updated_at: Time.current)
      Favorite.where(sale_order_id: id).update_all(sale_order_id: nil, updated_at: Time.current)
      InventoryAssignmentLog.where(sale_order_id: id).update_all(sale_order_id: nil)

      destroy_converted_carts!(id)
    end

    # El carrito de la tienda que se convirtió en este pedido. Su estado
    # 'converted' exige sale_order_id (check constraint), así que no se puede
    # desligar: se borra con sus líneas (las retenciones caen en cascada).
    def destroy_converted_carts!(id)
      cart_ids = ShoppingCart.where(sale_order_id: id).ids
      return if cart_ids.empty?

      # Carritos anónimos que se fusionaron en éste al iniciar sesión: apuntan
      # a él (merged_into_cart_id) y ya están cerrados; caen con él.
      frontier = cart_ids
      while (merged = ShoppingCart.where(merged_into_cart_id: frontier).where.not(id: cart_ids).ids).any?
        cart_ids += merged
        frontier = merged
      end

      CartSessionImport.where(shopping_cart_id: cart_ids).delete_all
      ShoppingCartItem.where(shopping_cart_id: cart_ids).delete_all
      # Primero los fusionados (hijos) y al final los convertidos (padres).
      cart_ids.reverse_each { |cart_id| ShoppingCart.where(id: cart_id).delete_all }
    end
  end
end
