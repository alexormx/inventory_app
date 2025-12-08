# frozen_string_literal: true

module Preorders
  class PreorderAllocator
    # Si newly_available_units no se pasa, intentará asignar todas las piezas libres (available + in_transit)
    def initialize(product, newly_available_units: nil)
      @product = product
      @units   = newly_available_units
    end

    # Método de clase para procesar múltiples productos
    # @param product_ids [Array<Integer>] IDs de productos que tienen nuevo inventario disponible
    # @return [Hash] { product_id => count_assigned }
    def self.batch_allocate(product_ids)
      return {} if product_ids.blank?

      results = {}
      product_ids.uniq.each do |product_id|
        product = Product.find_by(id: product_id)
        next unless product

        begin
          allocator = new(product)
          allocator.call
          results[product_id] = true
        rescue StandardError => e
          Rails.logger.error "[Preorders::PreorderAllocator] batch_allocate error for product #{product_id}: #{e.class} #{e.message}"
          results[product_id] = false
        end
      end
      results
    end

    def call
      return unless @product

      remaining = if @units
                    @units.to_i
                  else
                    Inventory.where(product_id: @product.id, status: %i[available in_transit], sale_order_id: nil).count
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
          order_date: Time.zone.today,
          tax_rate: 0,
          subtotal: 0,
          total_tax: 0,
          total_order_value: 0,
          status: 'Pending'
        )
        soi = so.sale_order_items.find_or_initialize_by(product_id: @product.id)
        soi.quantity = soi.quantity.to_i + qty
        soi.unit_cost ||= @product.average_purchase_cost.to_f
        soi.unit_final_price ||= @product.price.to_f if @product.respond_to?(:price)
        soi.preorder_quantity = soi.preorder_quantity.to_i + qty
        soi.save!

        # El callback sync_inventory_for_sale en SaleOrderItem ya asignará inventory automáticamente
        # Verificar cuánto inventario fue efectivamente asignado
        assigned_inventories = Inventory.where(product_id: @product.id, sale_order_id: so.id)
        assigned_count = assigned_inventories.count

        # Marcar asignación total o parcial y actualizar sale_order en reservation
        if assigned_count >= qty
          # Se asignó todo
          reservation.update!(status: :assigned, assigned_at: Time.current, quantity: qty, sale_order: so)
          remaining -= qty
        elsif assigned_count.positive?
          # Asignación parcial: dividir reservation
          reservation.update!(status: :assigned, assigned_at: Time.current, quantity: assigned_count, sale_order: so)
          PreorderReservation.create!(
            product: @product,
            user: reservation.user,
            sale_order: nil,
            quantity: (qty - assigned_count),
            status: :pending,
            reserved_at: Time.current
          )
          remaining -= assigned_count
        end
        # Si assigned_count == 0, no se asignó nada (no hay inventory disponible)
      end
    rescue StandardError => e
      Rails.logger.error "[Preorders::PreorderAllocator] #{e.class}: #{e.message}"
    end
  end
end
