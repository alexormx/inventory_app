# frozen_string_literal: true

module SaleOrders
  # Cancela una orden pendiente y no pagada, liberando únicamente reservaciones.
  # Uso:
  #   SaleOrders::CancelOrderService.new(sale_order).call
  #
  # Retorna: la sale_order actualizada
  # Lanza: CancellationBlocked cuando requiere un flujo controlado de devolución/reembolso.
  class CancelOrderService
    class CancellationBlocked < StandardError; end

    RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze
    FULFILLED_INVENTORY_STATUSES = %w[sold pre_sold].freeze
    RELEASABLE_INVENTORY_STATUSES = %w[reserved pre_reserved].freeze

    attr_reader :sale_order

    def initialize(sale_order)
      @sale_order = sale_order
    end

    def call
      canceled_now = false

      ActiveRecord::Base.transaction do
        sale_order.lock!
        next if sale_order.status == 'Canceled'

        block_if_payment_review_required!
        block_unless_pending!

        sale_order_item_ids = sale_order.sale_order_items.ids
        linked_inventories = linked_inventory_scope(sale_order_item_ids).lock.to_a
        block_if_inventory_ownership_conflicts!(linked_inventories, sale_order_item_ids)
        block_if_fulfilled_inventory_exists!(linked_inventories)

        release_inventories!(linked_inventories)
        cancel_linked_preorders!(sale_order_item_ids)

        cancel_sale_order!
        update_product_stats!
        canceled_now = true

        Rails.logger.info "[CancelOrderService] SO #{sale_order.id} canceled, #{@released_count} inventories released"
      end

      allocate_to_pending_preorders! if canceled_now

      sale_order.reload
    end

    private

    # Único punto de la aplicación autorizado a llevar una orden viva a Canceled.
    # La autorización se concede sobre esta instancia y se retira enseguida, de
    # modo que un objeto reutilizado no arrastre el permiso.
    def cancel_sale_order!
      sale_order.cancellation_authorized = true
      sale_order.update!(status: 'Canceled')
    ensure
      sale_order.cancellation_authorized = false
    end

    def block_if_payment_review_required!
      received_payment = sale_order.payments.lock
                                   .where(status: RECEIVED_PAYMENT_STATUSES)
                                   .where('amount > 0')
                                   .exists?
      return unless received_payment

      raise CancellationBlocked,
            'La orden tiene pagos recibidos o reembolsados. Requiere revisión de pago y reembolso; no se canceló ni se liberó inventario.'
    end

    def block_unless_pending!
      return if sale_order.status == 'Pending'

      if ['In Transit', 'Delivered'].include?(sale_order.status)
        raise CancellationBlocked,
              'La orden ya fue enviada o entregada. Requiere un flujo controlado de devolución y reembolso; no se modificó el inventario.'
      end

      raise CancellationBlocked,
            'Solo una orden pendiente y sin pagos recibidos puede usar esta cancelación. La orden requiere revisión administrativa.'
    end

    def linked_inventory_scope(sale_order_item_ids)
      return Inventory.where(sale_order_id: sale_order.id) if sale_order_item_ids.empty?

      Inventory.where(
        'sale_order_id = :sale_order_id OR sale_order_item_id IN (:sale_order_item_ids)',
        sale_order_id: sale_order.id,
        sale_order_item_ids: sale_order_item_ids
      )
    end

    def block_if_inventory_ownership_conflicts!(inventories, sale_order_item_ids)
      conflict = inventories.any? do |inventory|
        (inventory.sale_order_id.present? && inventory.sale_order_id != sale_order.id) ||
          (inventory.sale_order_item_id.present? && sale_order_item_ids.exclude?(inventory.sale_order_item_id))
      end
      return unless conflict

      raise CancellationBlocked,
            'No se pudo validar la propiedad del inventario de la orden. Requiere revisión de inventario antes de cancelar.'
    end

    def block_if_fulfilled_inventory_exists!(inventories)
      return if inventories.none? { |inventory| inventory.status.in?(FULFILLED_INVENTORY_STATUSES) }

      raise CancellationBlocked,
            'La orden tiene inventario vendido o pre-vendido. Requiere devolución y revisión de reembolso; no se modificó el inventario.'
    end

    def cancel_linked_preorders!(sale_order_item_ids)
      linked_by_order = PreorderReservation.where(sale_order_id: sale_order.id)
      linked_preorders = if sale_order_item_ids.empty?
                           linked_by_order
                         else
                           linked_by_line = PreorderReservation.where(
                             sale_order_id: nil,
                             sale_order_item_id: sale_order_item_ids
                           )
                           linked_by_order.or(linked_by_line)
                         end

      linked_preorders.where(status: %i[pending assigned]).update_all(
        status: PreorderReservation.statuses[:cancelled],
        cancelled_at: Time.current,
        updated_at: Time.current
      )
    end

    def release_inventories!(linked_inventories)
      releasable_ids = linked_inventories.filter_map do |inventory|
        inventory.id if inventory.status.in?(RELEASABLE_INVENTORY_STATUSES)
      end
      releasable = Inventory.where(id: releasable_ids)
      @product_ids = releasable.distinct.pluck(:product_id)

      on_hand = releasable.where(status: :reserved)
      incoming = releasable.where(status: :pre_reserved)

      on_hand_count = on_hand.update_all(
        status: Inventory.statuses[:available],
        sale_order_id: nil,
        sale_order_item_id: nil,
        sold_price: nil,
        status_changed_at: Time.current,
        updated_at: Time.current
      )
      incoming_count = incoming.update_all(
        status: Inventory.statuses[:in_transit],
        sale_order_id: nil,
        sale_order_item_id: nil,
        sold_price: nil,
        status_changed_at: Time.current,
        updated_at: Time.current
      )
      @released_count = on_hand_count + incoming_count

      Rails.logger.info "[CancelOrderService] SO #{sale_order.id}: Released #{@released_count} inventories"
    end

    def update_product_stats!
      return if @product_ids.blank?

      @product_ids.each do |product_id|
        Products::UpdateStatsService.new(Product.find(product_id)).call
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn "[CancelOrderService] Product #{product_id} not found for stats update"
      end
    end

    def allocate_to_pending_preorders!
      return if @product_ids.blank?

      Rails.logger.info "[CancelOrderService] Allocating released inventory to pending preorders for #{@product_ids.count} products"
      results = Preorders::PreorderAllocator.batch_allocate(@product_ids)

      success_count = results.values.count(true)
      Rails.logger.info "[CancelOrderService] Preorder allocation completed: #{success_count}/#{@product_ids.count} products processed"
    end
  end
end
