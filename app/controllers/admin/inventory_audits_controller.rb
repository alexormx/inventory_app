# frozen_string_literal: true

module Admin
  class InventoryAuditsController < ApplicationController
    before_action :authorize_admin!

    def index
      @assignment_logs = InventoryAssignmentLog.recent.limit(50)
      @pending_assignments = pending_assignments_summary
    end

    def fix_inconsistencies
      # Placeholder: implementar lógica de corrección posteriormente
      redirect_to admin_inventory_audit_path, notice: 'Fix inconsistencies job en cola (placeholder).'
    end

    def fix_missing_so_lines
      redirect_to admin_inventory_audit_path, notice: 'Fix missing sale order lines en cola (placeholder).'
    end

    # POST /admin/inventory_audit/auto_assign
    def auto_assign
      dry_run = params[:dry_run] == '1'

      result = SaleOrders::AutoAssignInventoryService.new(
        triggered_by: 'admin_action',
        dry_run: dry_run
      ).call

      if result.success?
        if dry_run
          flash[:notice] = "Dry Run: #{result.assigned_count} piezas se asignarían, #{result.pending_count} quedarían pendientes."
        else
          flash[:success] = "Auto-asignación completada: #{result.assigned_count} piezas asignadas, #{result.pending_count} pendientes."
        end
      else
        flash[:alert] = "Errores durante auto-asignación: #{result.errors.join(', ')}"
      end

      redirect_to admin_inventory_audit_path
    end

    private

    def pending_assignments_summary
      # SOIs que necesitan más inventario del que tienen asignado
      SaleOrderItem
        .joins(:sale_order)
        .where(sale_orders: { status: ['Pending', 'Confirmed'] })
        .select('sale_order_items.*, sale_orders.status as so_status')
        .map do |soi|
          assigned = soi.inventories.count
          needed = soi.quantity
          next if assigned >= needed

          {
            sale_order_id: soi.sale_order_id,
            sale_order_item_id: soi.id,
            product_id: soi.product_id,
            product_sku: soi.product&.sku,
            product_name: soi.product&.name,
            quantity_needed: needed,
            quantity_assigned: assigned,
            quantity_pending: needed - assigned
          }
        end.compact
    end
  end
end

