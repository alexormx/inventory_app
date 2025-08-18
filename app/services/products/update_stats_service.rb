class Products::UpdateStatsService
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
                    .where.not(purchase_orders: { status: "Canceled" })

    # Quantities
    total_qty = items.sum(:quantity)
    @product.total_purchase_quantity = total_qty

    # Value in MXN using composed unit cost (includes shipping/tax/other prorated)
    # Strictly use MXN-based fields; do NOT fall back to origin-currency unit_cost.
    total_value_mxn =
      items.sum("COALESCE(total_line_cost_in_mxn, quantity * unit_compose_cost_in_mxn, 0)")

    @product.total_purchase_value = total_value_mxn
    @product.average_purchase_cost = total_qty.to_i.zero? ? 0 : (total_value_mxn / total_qty)

  # Last purchase info based on composed MXN unit cost when available
  # Safe cross-DB ordering (SQLite/Postgres): prefer updated_at then id; take the last one
  last_item = items.order(:updated_at, :id)&.last
  @product.last_purchase_cost = (last_item&.unit_compose_cost_in_mxn || 0)
    @product.last_purchase_date = last_item&.purchase_order&.order_date

    @product.total_purchase_order = items.distinct.count(:purchase_order_id)
  end

  def update_sales_stats
    items = @product.sale_order_items.joins(:sale_order)
                .where(sale_orders: { status: %w[Shipped Delivered] })

    @product.total_sales_quantity = items.sum(:quantity)
    @product.total_sales_value = items.sum("quantity * unit_final_price")
    @product.average_sales_price = @product.total_sales_quantity.zero? ? 0 :
                                    @product.total_sales_value / @product.total_sales_quantity
    @product.last_sales_price = items.last&.unit_final_price || 0
    @product.last_sales_date = items.last&.sale_order&.order_date
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

