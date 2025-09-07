module Preorders
  class PreorderAllocator
    def initialize(product, newly_available_units: nil)
      @product = product
      @units = newly_available_units
    end

    def call
      return unless @product&.preorder_available

      # Usar todas las disponibles si no se especifica recuento
  # Contar piezas potencialmente asignables (available + in_transit, sin SO)
  remaining = @units || Inventory.where(product_id: @product.id, status: [:available, :in_transit], sale_order_id: nil).count
      return if remaining <= 0

      PreorderReservation.fifo_pending.where(product_id: @product.id).find_each do |reservation|
        break if remaining <= 0

        qty = [reservation.quantity.to_i, remaining].min

        # Encontrar o crear una Sale Order asociada (opcional según negocio)
        so = reservation.sale_order || SaleOrder.create!(
          user: reservation.user,
          order_date: Date.today,
          tax_rate: 0,
          subtotal: 0,
          total_tax: 0,
          total_order_value: 0,
          status: "Pending"
        )

        # Asegurar línea en SO
        soi = so.sale_order_items.find_or_initialize_by(product_id: @product.id)
        soi.quantity = soi.quantity.to_i + qty
        soi.unit_cost ||= @product.average_purchase_cost.to_f
        soi.unit_final_price ||= @product.price.to_f
        soi.preorder_quantity = soi.preorder_quantity.to_i + qty
        soi.save!

        # Asignar inventario available/in_transit -> pre_* según estado de SO
        items = Inventory.where(product_id: @product.id, sale_order_id: nil, status: [:available, :in_transit]).limit(qty)
        assigned_count = 0
        items.each do |inv|
          target_status = if so.status == "Confirmed"
                            inv.status == "in_transit" ? :pre_sold : :pre_sold
                          else
                            inv.status == "in_transit" ? :pre_reserved : :pre_reserved
                          end
          inv.update!(
            status: target_status,
            sale_order_id: so.id,
            status_changed_at: Time.current
          )
          assigned_count += 1
        end
        if assigned_count > 0
          reservation.update!(status: :assigned, assigned_at: Time.current)
        end
        remaining -= assigned_count
      end
    rescue => e
      Rails.logger.error "[Preorders::PreorderAllocator] #{e.class}: #{e.message}"
    end
  end
end
module Preorders
  class PreorderAllocator
    # Asigna nuevo stock disponible a preorders pendientes en orden FIFO
    def initialize(product, newly_available_units:)
      @product = product
      @remaining = newly_available_units.to_i
    end

    def call
      return if @remaining <= 0
      PreorderReservation.fifo_pending.where(product: @product).find_each do |res|
        break if @remaining <= 0
        fulfill_qty = [res.quantity, @remaining].min
        @remaining -= fulfill_qty
        if fulfill_qty == res.quantity
          # Asignar completamente
          res.update!(status: :assigned, assigned_at: Time.current)
          # Futuro: crear / vincular sale order aquí o notificar usuario
        else
          # Caso parcial (split). Por simplicidad marcamos asignada parcial y ajustamos.
          # Alternativa: crear una reserva nueva para remanente.
          remaining = res.quantity - fulfill_qty
          res.update!(quantity: fulfill_qty, status: :assigned, assigned_at: Time.current)
          PreorderReservation.create!(product: @product, user: res.user, quantity: remaining, status: :pending, reserved_at: Time.current)
        end
      end
    end
  end
end
