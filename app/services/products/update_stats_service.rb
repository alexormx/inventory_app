# frozen_string_literal: true

module Products
  class UpdateStatsService
    def initialize(product)
      @product = product
    end

    def call
      update_purchase_stats
      update_sales_stats
      update_derived_metrics
      @product.save!
    end

    private

    def update_purchase_stats
      items = @product.purchase_order_items.joins(:purchase_order)
                      .where.not(purchase_orders: { status: 'Canceled' })

      po_qty = items.sum(:quantity).to_i
      # Value in MXN using composed unit cost (includes shipping/tax/other prorated)
      # Strictly use MXN-based fields; do NOT fall back to origin-currency unit_cost.
      po_value = items.sum('COALESCE(total_line_cost_in_mxn, quantity * unit_compose_cost_in_mxn, 0)').to_d

      # Inventarios sin PO (coleccionables agregados manualmente vía quick_add, etc.)
      # Se cuenta cada pieza como 1 unidad a su purchase_cost.
      manual_invs  = @product.inventories.where(purchase_order_item_id: nil).where('purchase_cost > 0')
      manual_qty   = manual_invs.count
      manual_value = manual_invs.sum(:purchase_cost).to_d

      total_qty   = po_qty + manual_qty
      total_value = po_value + manual_value

      @product.total_purchase_quantity = total_qty
      @product.total_purchase_value    = total_value
      @product.average_purchase_cost   = total_qty.zero? ? 0 : (total_value / total_qty)

      # Última compra: comparar el más reciente de PO-items vs inventario manual
      last_po_item = items.order(:updated_at, :id).last
      last_manual  = manual_invs.order(:created_at, :id).last

      po_time     = last_po_item&.updated_at
      manual_time = last_manual&.created_at

      if po_time && (manual_time.nil? || po_time >= manual_time)
        @product.last_purchase_cost = (last_po_item&.unit_compose_cost_in_mxn || 0)
        @product.last_purchase_date = last_po_item&.purchase_order&.order_date
      elsif last_manual
        @product.last_purchase_cost = last_manual.purchase_cost || 0
        @product.last_purchase_date = last_manual.created_at.to_date
      else
        @product.last_purchase_cost = 0
        @product.last_purchase_date = nil
      end

      @product.total_purchase_order = items.distinct.count(:purchase_order_id)
    end

    def update_sales_stats
      items = @product.sale_order_items.joins(:sale_order)
                      .where(sale_orders: { status: ['Pending', 'Confirmed', 'In Transit', 'Delivered'] })

      @product.total_sales_quantity = items.sum(:quantity)
      @product.total_sales_value = items.sum('quantity * unit_final_price')
      @product.average_sales_price = if @product.total_sales_quantity.zero?
                                       0
                                     else
                                       @product.total_sales_value / @product.total_sales_quantity
                                     end
      last_item = items.order(:updated_at, :id).last
      @product.last_sales_price = last_item&.unit_final_price || 0
      @product.last_sales_date = last_item&.sale_order&.order_date
      @product.total_sales_order = items.distinct.count(:sale_order_id)
      @product.total_units_sold = @product.total_sales_quantity
    end

    def update_derived_metrics
      remaining_stock = @product.total_purchase_quantity - @product.total_sales_quantity

      @product.current_profit = @product.total_sales_value - @product.total_purchase_value
      @product.current_inventory_value = remaining_stock * @product.average_purchase_cost
      @product.projected_sales_value = remaining_stock * @product.selling_price
      @product.projected_profit = @product.current_profit + @product.projected_sales_value
    end
  end
end
