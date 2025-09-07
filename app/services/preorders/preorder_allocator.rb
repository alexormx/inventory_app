module Preorders
  class PreorderAllocator
    # Si newly_available_units no se pasa, intentará asignar todas las piezas libres (available + in_transit)
    def initialize(product, newly_available_units: nil)
      @product = product
      @units   = newly_available_units
    end

    def call
      return unless @product

      remaining = if @units
                    @units.to_i
                  else
                    Inventory.where(product_id: @product.id, status: [:available, :in_transit], sale_order_id: nil).count
                  end
      return if remaining <= 0

      pending_scope = PreorderReservation.fifo_pending.where(product_id: @product.id)
      return if pending_scope.none?

      pending_scope.find_each do |reservation|
        break if remaining <= 0

        qty = [reservation.quantity.to_i, remaining].min

        # Asegurar SO y línea
        so = reservation.sale_order || SaleOrder.create!(
          user: reservation.user,
          order_date: Date.today,
          tax_rate: 0,
          subtotal: 0,
          total_tax: 0,
          total_order_value: 0,
          status: "Pending"
        )
        soi = so.sale_order_items.find_or_initialize_by(product_id: @product.id)
        soi.quantity = soi.quantity.to_i + qty
        soi.unit_cost ||= @product.average_purchase_cost.to_f
        soi.unit_final_price ||= @product.price.to_f if @product.respond_to?(:price)
        soi.preorder_quantity = soi.preorder_quantity.to_i + qty
        soi.save!

        # Asignar available primero como reserved
        to_assign = qty
        avl_items = Inventory.where(product_id: @product.id, sale_order_id: nil, status: :available).limit(to_assign)
        avl_items.each do |inv|
          inv.update!(
            status: :reserved,
            sale_order_id: so.id,
            sale_order_item_id: soi.id,
            status_changed_at: Time.current
          )
          to_assign -= 1
        end

        # Luego asignar in_transit como pre_* según estado de la SO
        if to_assign > 0
          it_items = Inventory.where(product_id: @product.id, sale_order_id: nil, status: :in_transit).limit(to_assign)
          it_items.each do |inv|
            target_status = (so.status == "Confirmed") ? :pre_sold : :pre_reserved
            inv.update!(
              status: target_status,
              sale_order_id: so.id,
              sale_order_item_id: soi.id,
              status_changed_at: Time.current
            )
            to_assign -= 1
          end
        end

        # Marcar asignación total o parcial
        assigned_amount = (qty - to_assign)
        if assigned_amount > 0
          reservation.update!(status: :assigned, assigned_at: Time.current, quantity: assigned_amount)
          if to_assign > 0
            # dividir: crear nueva reserva por el remanente no asignado
            remaining_part = to_assign
            PreorderReservation.create!(product: @product, user: reservation.user, sale_order: so, quantity: remaining_part, status: :pending, reserved_at: Time.current)
          end
        end

        remaining -= (qty - to_assign)
      end
    rescue => e
      Rails.logger.error "[Preorders::PreorderAllocator] #{e.class}: #{e.message}"
    end
  end
end
