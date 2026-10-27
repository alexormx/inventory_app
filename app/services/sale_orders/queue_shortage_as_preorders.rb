# frozen_string_literal: true

module SaleOrders
  # Un pedido capturado a mano en el admin puede pedir más piezas de las que
  # hay. Ese faltante entra a la misma cola FIFO que las preventas del checkout
  # (preorder_quantity + PreorderReservation), así queda visible en
  # /admin/preorders y Preorders::PreorderAllocator lo atiende en cuanto llega
  # oferta, aunque la pieza recibida todavía no tenga ubicación.
  #
  # Sólo lo llama el admin. El checkout ya decide su preventa antes de crear la
  # línea, y su reserva estricta debe fallar ante un faltante inesperado en vez
  # de convertirlo en una preventa que el cliente no aceptó.
  class QueueShortageAsPreorders
    ACTIVE_STATUSES = %w[Pending Confirmed].freeze

    def self.call(sale_order) = new(sale_order).call

    def initialize(sale_order)
      @sale_order = sale_order
    end

    # @return [Integer] piezas puestas en la cola
    def call
      return 0 unless ACTIVE_STATUSES.include?(@sale_order.status)

      lines = @sale_order.sale_order_items.reload.sort_by(&:product_id)
      lines.sum { |line| queue_line(line) }
    end

    private

    def queue_line(line)
      queued = 0
      ActiveRecord::Base.transaction do
        # Mismo orden de bloqueos que PreorderAllocator: producto, luego línea.
        product = Product.lock.find(line.product_id)
        locked_line = SaleOrderItem.lock.find(line.id)
        queued = locked_line.immediate_quantity - locked_line.inventory_units.count
        next if queued <= 0

        locked_line.update!(preorder_quantity: locked_line.preorder_quantity.to_i + queued)
        PreorderReservation.create!(
          product: product,
          user: @sale_order.user,
          sale_order: @sale_order,
          sale_order_item: locked_line,
          quantity: queued,
          status: :pending,
          notes: 'Generada desde pedido manual del admin'
        )
        # La cola reemplaza a la nota de faltante: la nota no se actualizaría
        # cuando el asignador complete la línea.
        @sale_order.remove_pending_note_for(locked_line)
        Preorders::PreorderAllocator.new(product).call
      end
      queued
    end
  end
end
