# frozen_string_literal: true

module Preorders
  class PreorderAllocator
    # Si newly_available_units no se pasa, intentará asignar todas las piezas
    # libres (available + in_transit).
    #
    # Toda asignación respeta DOS topes a la vez:
    #
    #   1. newly_available_units es un presupuesto COMPARTIDO por llamada. Lo
    #      ha sido desde que existe la clase: N unidades nuevas reparten N
    #      piezas en total, no N por condición.
    #   2. Cada condición no puede exceder su propia oferta real. Una pieza
    #      mint no autoriza ni satisface demanda brand_new.
    #
    # `condition` acota además la llamada a una sola condición: quien publica
    # una pieza sabe de qué condición es, y esa oferta sólo puede satisfacer
    # demanda de la MISMA condición.
    def initialize(product, newly_available_units: nil, condition: nil)
      @product   = product
      @units     = newly_available_units
      @condition = condition.presence && Inventories::Availability.normalize_condition(condition)
    end

    # Método de clase para procesar múltiples productos
    # @param product_ids [Array<Integer>] IDs de productos que tienen nuevo inventario disponible
    # @return [Hash] { product_id => count_assigned }
    def self.batch_allocate(product_ids)
      return {} if product_ids.blank?

      results = {}
      product_ids.uniq.sort.each do |product_id|
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

      ActiveRecord::Base.transaction do
        # Product is the per-SKU serialization lock shared with checkout and
        # every supply boundary. Holding it before demand/inventory locks keeps
        # a newer checkout from overtaking older committed demand.
        @product = Product.lock.find(@product.id)
        # Dos topes independientes, ambos obligatorios:
        #   supply -> cuántas piezas existen DE CADA CONDICIÓN (corrección nueva)
        #   pool   -> cuántas unidades puede repartir esta llamada en total
        #             (semántica histórica de newly_available_units)
        supply = supply_by_condition
        supply = supply.slice(@condition) if @condition
        pool = @units ? @units.to_i : supply.values.sum
        next 0 if pool <= 0 || supply.empty?

        pending = PreorderReservation.fifo_pending
                                     .where(product_id: @product.id)
                                     .lock
                                     .to_a
        next 0 if pending.empty?

        assigned_total = 0
        pending.each do |reservation|
          break if pool <= 0

          # La condición de la demanda vive en la línea de venta, que es la
          # misma que consume InventoryServices::ReserveSaleOrderItem.
          condition = demand_condition(reservation)
          limit = [supply[condition].to_i, pool].min
          next if limit <= 0

          assigned = allocate_to_originating_line(reservation, limit)
          assigned_total += assigned
          supply[condition] = supply[condition].to_i - assigned
          pool -= assigned
        end
        assigned_total
      end
    rescue StandardError => e
      Rails.logger.error "[Preorders::PreorderAllocator] #{e.class}: #{e.message}"
      raise
    end

    private

    # Presupuesto de oferta POR CONDICIÓN. La semántica de oferta de preventa
    # no cambia -- sigue siendo customer_sellable (disponible ahora O en
    # tránsito, ver Inventory#customer_sellable) -- lo único que se corrige es
    # que ya no se agrega entre condiciones: una pieza mint no puede autorizar
    # ni satisfacer demanda brand_new.
    #
    # Es la MISMA relación que antes, sólo agrupada; no añade una consulta
    # extra ni toca el orden de bloqueos.
    def supply_by_condition
      Inventory.customer_sellable
               .where(product_id: @product.id)
               .group(:item_condition)
               .count
               .each_with_object(Hash.new(0)) do |(condition, count), acc|
        acc[Inventories::Availability.normalize_condition(condition)] += count
      end
    end

    def demand_condition(reservation)
      Inventories::Availability.normalize_condition(reservation.sale_order_item&.item_condition)
    end

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
