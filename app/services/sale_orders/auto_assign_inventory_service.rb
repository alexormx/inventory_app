# frozen_string_literal: true

module SaleOrders
  # Servicio para asignar automáticamente inventario disponible a SaleOrderItems
  # que aún tienen piezas pendientes de asignación.
  #
  # Uso:
  #   result = SaleOrders::AutoAssignInventoryService.new(
  #     triggered_by: 'job_scheduled',
  #     dry_run: false
  #   ).call
  #
  class AutoAssignInventoryService
    Result = Struct.new(:success, :assigned_count, :pending_count, :errors, :assignments, keyword_init: true) do
      def success?
        success
      end
    end

    # @param triggered_by [String] Quién disparó la asignación (job_scheduled, admin_action, etc.)
    # @param dry_run [Boolean] Si es true, no hace cambios reales
    # @param limit [Integer] Límite de SOIs a procesar
    # @param sale_order_ids [Array<String>] Opcional: limitar a SOs específicas
    def initialize(triggered_by: 'system', dry_run: false, limit: 1000, sale_order_ids: nil)
      @triggered_by = triggered_by
      @dry_run = dry_run
      @limit = limit
      @sale_order_ids = sale_order_ids
      @assignments = []
      @errors = []
    end

    def call
      assigned_total = 0
      pending_total = 0

      ActiveRecord::Base.transaction do
        sois_needing = sale_order_items_needing_inventory
        sois_to_process = sois_needing.first(@limit)

        sois_to_process.each do |soi|
          result = assign_inventory_to_item(soi)
          assigned_total += result[:assigned]
          pending_total += result[:pending]
        end

        # Log de asignaciones si no es dry_run
        unless @dry_run || @assignments.empty?
          InventoryAssignmentLog.log_assignment_run(
            triggered_by: @triggered_by,
            assignments: @assignments
          )
        end

        raise ActiveRecord::Rollback if @dry_run
      end

      Result.new(
        success: @errors.empty?,
        assigned_count: assigned_total,
        pending_count: pending_total,
        errors: @errors,
        assignments: @assignments
      )
    rescue StandardError => e
      Rails.logger.error "[AutoAssignInventoryService] Error: #{e.class}: #{e.message}"
      Result.new(success: false, assigned_count: 0, pending_count: 0, errors: [e.message], assignments: [])
    end

    private

    def sale_order_items_needing_inventory
      # SOIs de órdenes activas (Pending, Confirmed) que tienen menos inventario
      # asignado del que necesitan
      scope = SaleOrderItem.joins(:sale_order)
                           .includes(:product, :sale_order)
                           .where(sale_orders: { status: ['Pending', 'Confirmed'] })

      scope = scope.where(sale_orders: { id: @sale_order_ids }) if @sale_order_ids.present?

      # Filtrar solo los que tienen piezas pendientes de asignar
      scope.select do |soi|
        assigned = Inventory.where(sale_order_id: soi.sale_order_id, product_id: soi.product_id).count
        needed = soi.quantity.to_i - soi.preorder_quantity.to_i - soi.backordered_quantity.to_i
        assigned < needed
      end
    end

    def assign_inventory_to_item(soi)
      assigned_count = 0
      product = soi.product
      sale_order = soi.sale_order

      # Calcular cuántas piezas necesita (descontando preorder/backorder)
      immediate_needed = soi.quantity.to_i - soi.preorder_quantity.to_i - soi.backordered_quantity.to_i
      currently_assigned = Inventory.where(sale_order_id: sale_order.id, product_id: product.id).count
      to_assign = immediate_needed - currently_assigned

      return { assigned: 0, pending: 0 } if to_assign <= 0

      # Buscar inventario disponible
      # Filtra por condición si el SOI especifica una
      available_scope = Inventory.where(product_id: product.id, status: :available, sale_order_id: nil)

      # Si el SOI tiene condición específica, filtrar por ella
      if soi.respond_to?(:item_condition) && soi.item_condition.present?
        available_scope = available_scope.where(item_condition: soi.item_condition)
      end

      available_inventory = available_scope.order(created_at: :asc).limit(to_assign)

      available_inventory.each do |inv|
        # Contar la asignación (para dry_run) pero solo actualizar si no es dry_run
        assigned_count += 1

        @assignments << {
          sale_order: sale_order,
          sale_order_item: soi,
          product: product,
          inventory: inv,
          type: :auto_assignment,
          quantity_assigned: 1,
          quantity_pending: [to_assign - assigned_count, 0].max,
          notes: "Auto-assigned inv ##{inv.id} to SO #{sale_order.id}"
        }

        next if @dry_run

        begin
          inv.update!(
            status: :reserved,
            sale_order_id: sale_order.id,
            sale_order_item_id: soi.id,
            status_changed_at: Time.current
          )
        rescue StandardError => e
          @errors << "Failed to assign inv ##{inv.id}: #{e.message}"
          assigned_count -= 1 # Revertir el conteo si falló
        end
      end

      pending = to_assign - assigned_count
      { assigned: assigned_count, pending: pending }
    end
  end
end
