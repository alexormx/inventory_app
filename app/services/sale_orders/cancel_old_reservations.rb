# frozen_string_literal: true

module SaleOrders
  class CancelOldReservations
    # Contract:
    # inputs: sale_order (SaleOrder), current_user (User optional), reason (String)
    # behavior: libera inventario reservado/pre_* de esta SO (no toca sold),
    #           reduce/cancela preventas asociadas, registra CanceledOrderItem por producto,
    #           ajusta preorder_quantity/backordered_quantity en SOI y recalcula totales.
    # seguridad: si hay sold o shipment/pagos completados y status Delivered, no cambia sold.
    Result = Struct.new(:ok, :released_units, :preorders_cancelled, :items_logged, :errors, keyword_init: true)

    def initialize(sale_order:, reason:, actor: nil)
      @sale_order = sale_order
      @reason = reason.presence || 'Manual cancellation of old reservations'
      @actor = actor
    end

    def call
      errors = []
      released = 0
      preorders_cancelled = 0
      items_logged = 0

      so = @sale_order

      ApplicationRecord.transaction do
        # 1) No tocar vendidos; abortar si intentan cancelar una SO ya Delivered completa sin intención
        # Nota: Permitimos cancelar reservas aun si Delivered, siempre que no toquemos sold.

        # 2) Para cada línea, registrar CanceledOrderItem por la cantidad de reservas liberadas
        so.sale_order_items.includes(:product).find_each do |li|
          # Conteos actuales
          assigned_reserved = Inventory.where(sale_order_id: so.id, product_id: li.product_id, status: %i[reserved pre_reserved pre_sold]).count

          # 2a) Liberar reserved y pre_* -> available (mantener sold intacto)
          if assigned_reserved.positive?
            changed = Inventory.where(sale_order_id: so.id, product_id: li.product_id, status: %i[reserved pre_reserved pre_sold])
                               .update_all(status: Inventory.statuses[:available], sale_order_id: nil, sale_order_item_id: nil, status_changed_at: Time.current, updated_at: Time.current)
            released += changed.to_i

            # 2b) Registrar en CanceledOrderItem la cantidad liberada
            if changed.to_i.positive?
              CanceledOrderItem.create!(
                sale_order: so,
                product: li.product,
                canceled_quantity: changed.to_i,
                sale_price_at_cancellation: li.unit_final_price.to_d.presence || li.unit_cost.to_d,
                cancellation_reason: @reason,
                canceled_at: Time.current
              )
            end
            items_logged += 1 if changed.to_i.positive?
          end

          # 2c) Cancelar preventas asociadas a esta SO y producto
          #    y ajustar preorder_quantity de la línea
          if li.preorder_quantity.to_i.positive?
            to_cancel = li.preorder_quantity.to_i
            preorders_scope = PreorderReservation.where(product_id: li.product_id, sale_order_id: so.id, status: :pending)
            cancelled_count = 0
            preorders_scope.order(:reserved_at, :id).find_each do |pre|
              break if to_cancel <= 0

              if pre.quantity <= to_cancel
                pre.update!(status: :cancelled, cancelled_at: Time.current, notes: [pre.notes, @reason].compact.join(' | '))
                cancelled_count += pre.quantity
                to_cancel -= pre.quantity
              else
                # reducir cantidad y marcar cancelado si llega a cero
                # Para mantenerlo simple, dividimos registro
                remain = pre.quantity - to_cancel
                pre.update!(quantity: remain)
                if to_cancel.positive?
                  CanceledOrderItem.create!(
                    sale_order: so,
                    product_id: li.product_id,
                    canceled_quantity: to_cancel,
                    sale_price_at_cancellation: li.unit_final_price.to_d.presence || li.unit_cost.to_d,
                    cancellation_reason: "Preorder cancelled: #{@reason}",
                    canceled_at: Time.current
                  )
                end
                cancelled_count += to_cancel
                to_cancel = 0
              end
            end
            if cancelled_count.positive?
              new_qty = [li.preorder_quantity.to_i - cancelled_count, 0].max
              li.update_columns(preorder_quantity: new_qty, updated_at: Time.current)
              preorders_cancelled += cancelled_count
            end
          end
        end

        # 3) No eliminamos líneas; preservamos como historial. Si se desea, el admin puede luego editar cantidades manualmente.

        # 4) Si ya no quedan inventarios ligados (excepto sold), marcar la SO como Canceled
        remaining_non_sold = Inventory.where(sale_order_id: so.id).where.not(status: :sold).count
        so.update!(status: 'Canceled') if remaining_non_sold.zero? && so.status != 'Canceled'

        # 5) Recalcular totales de la SO
        so.recalculate_totals!(persist: true)
      end

      Result.new(ok: true, released_units: released, preorders_cancelled: preorders_cancelled, items_logged: items_logged, errors: errors)
    rescue StandardError => e
      Result.new(ok: false, released_units: released, preorders_cancelled: preorders_cancelled, items_logged: items_logged, errors: [e.message])
    end
  end
end
