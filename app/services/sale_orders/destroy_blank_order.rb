# frozen_string_literal: true

module SaleOrders
  # Borra un pedido EN BLANCO: sin productos, sin piezas de inventario y sin
  # nada que lo referencie (pagos recibidos, envío, preventas, carrito
  # convertido, solicitudes de WhatsApp ni historial de asignación).
  #
  # Cualquier pedido con contenido se sigue manejando con Cancelar, que
  # conserva el historial; borrar solo limpia registros vacíos.
  class DestroyBlankOrder
    # Confirmed incluido: un pedido con total $0 se confirma solo (0 >= 0 en
    # fully_paid?), así quedan los pedidos en blanco creados desde el admin.
    DELETABLE_STATUSES = %w[Pending Confirmed Canceled].freeze
    RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze

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

        # Pagos pendientes/fallidos de un pedido vacío no representan dinero.
        Payment.where(sale_order_id: @sale_order.id).delete_all
        @sale_order.order_shipping_address&.destroy!
        @sale_order.destroy!
      end
      Result.new(destroyed: true, reasons: [])
    end

    def blocking_reasons
      id = @sale_order.id
      reasons = []
      reasons << 'solo se pueden borrar pedidos pendientes, confirmados o cancelados' unless DELETABLE_STATUSES.include?(@sale_order.status)
      reasons << 'tiene productos' if @sale_order.sale_order_items.exists?
      reasons << 'tuvo productos antes de cancelarse' if CanceledOrderItem.exists?(sale_order_id: id)
      reasons << 'tiene piezas de inventario asignadas' if Inventory.exists?(sale_order_id: id)
      reasons << 'tiene pagos recibidos o reembolsados' if @sale_order.payments.exists?(status: RECEIVED_PAYMENT_STATUSES)
      reasons << 'tiene un envío registrado' if Shipment.exists?(sale_order_id: id)
      reasons << 'tiene preventas ligadas' if PreorderReservation.exists?(sale_order_id: id)
      reasons << 'viene de un carrito de la tienda' if ShoppingCart.exists?(sale_order_id: id)
      reasons << 'está ligado a una solicitud de WhatsApp' if WhatsappRequest.exists?(sale_order_id: id)
      reasons << 'tiene favoritos marcados como comprados con este pedido' if Favorite.exists?(sale_order_id: id)
      reasons << 'tiene historial de inventario' if inventory_history?(id)
      reasons
    end

    private

    def inventory_history?(id)
      InventoryAssignmentLog.exists?(sale_order_id: id) ||
        InventoryEvent.exists?(previous_sale_order_id: id) ||
        InventoryEvent.exists?(new_sale_order_id: id)
    end
  end
end
