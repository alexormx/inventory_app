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
                  .where(purchase_orders: { status: %w[Received Completed] })

    @product.total_purchase_quantity = items.sum(:quantity)
    @product.total_purchase_value = items.sum("quantity * unit_cost")
    @product.average_purchase_cost = @product.total_purchase_quantity.zero? ? 0 :
                                      @product.total_purchase_value / @product.total_purchase_quantity
    @product.last_purchase_cost = items.last&.unit_cost || 0
    @product.last_purchase_date = items.last&.purchase_order&.order_date
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

