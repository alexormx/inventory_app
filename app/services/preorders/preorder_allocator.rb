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

        allocator = new(product)
        allocator.call
        results[product_id] = true
      end
      results
    end

    def call
      return 0 unless @product

      remaining = if @units
                    @units.to_i
                  else
                    Inventory.customer_sellable.where(product_id: @product.id).count
                  end
      return 0 if remaining <= 0

      pending_scope = PreorderReservation.fifo_pending.where(product_id: @product.id)
      return 0 if pending_scope.none?

      assigned_total = 0
      pending_scope.each do |reservation|
        break if remaining <= 0

        assigned = allocate_to_originating_line(reservation, remaining)
        assigned_total += assigned
        remaining -= assigned
      end
      assigned_total
    rescue StandardError => e
      Rails.logger.error "[Preorders::PreorderAllocator] #{e.class}: #{e.message}"
      raise
    end

    private

    def allocate_to_originating_line(reservation, limit)
      line = reservation.sale_order_item
      unless valid_origin?(reservation, line)
        Rails.logger.warn(
          "[Preorders::PreorderAllocator] Skipping unverified legacy reservation id=#{reservation.id}"
        )
        return 0
      end

      assigned = 0
      ActiveRecord::Base.transaction do
        locked_reservation = PreorderReservation.lock.find(reservation.id)
        next unless locked_reservation.pending?

        locked_line = SaleOrderItem.lock.find(line.id)
        target = [locked_reservation.quantity.to_i, limit.to_i, locked_line.preorder_quantity.to_i].min
        next if target <= 0

        assigned_before = locked_line.inventory_units.count
        locked_line.update!(preorder_quantity: locked_line.preorder_quantity.to_i - target)
        result = InventoryServices::ReserveSaleOrderItem.call(locked_line, strict: false)
        assigned = [[result.total_assigned - assigned_before, 0].max, target].min

        unassigned = target - assigned
        locked_line.update!(preorder_quantity: locked_line.preorder_quantity.to_i + unassigned) if unassigned.positive?
        record_assignment!(locked_reservation, assigned) if assigned.positive?
      end
      assigned
    end

    def valid_origin?(reservation, line)
      line.present? &&
        reservation.sale_order_id.present? &&
        line.sale_order_id == reservation.sale_order_id &&
        line.product_id == reservation.product_id
    end

    def record_assignment!(reservation, assigned)
      original_quantity = reservation.quantity.to_i
      reservation.update!(
        quantity: assigned,
        status: :assigned,
        assigned_at: Time.current
      )
      return unless assigned < original_quantity

      PreorderReservation.create!(
        product: reservation.product,
        user: reservation.user,
        sale_order: reservation.sale_order,
        sale_order_item: reservation.sale_order_item,
        quantity: original_quantity - assigned,
        status: :pending,
        reserved_at: reservation.reserved_at
      )
    end
  end
end
