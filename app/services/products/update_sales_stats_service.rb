# app/services/update_sales_stats_service.rb
module Products
  class UpdateSalesStatsService
    def initialize(product)
      @product = product
    end

    def call
      update_sales_data
      update_derived_metrics
      @product.save!
    end

    private

    def update_sales_data
      items = @product.sale_order_items.joins(:sale_order).where(sale_orders: { status: 'completed' })

      @product.total_sales_quantity = items.sum(:quantity)
      @product.total_sales_value = items.sum("quantity * unit_price")
      @product.average_sales_price = @product.total_sales_quantity > 0 ? @product.total_sales_value / @product.total_sales_quantity : 0.0

      last_item = items.order("sale_orders.order_date DESC").first
      if last_item
        @product.last_sales_price = last_item.unit_price
        @product.last_sales_date = last_item.sale_order.order_date
      end

      @product.total_sales_order = items.map(&:sale_order_id).uniq.count
    end

    def update_derived_metrics
      @product.current_profit = @product.total_sales_value - @product.total_purchase_value
      remaining_stock = @product.total_purchase_quantity - @product.total_sales_quantity
      @product.current_value = remaining_stock * @product.average_purchase_cost
      @product.projected_sales_value = remaining_stock * @product.selling_price
      @product.projected_profit = @product.current_profit + @product.projected_sales_value
    end
  end
end
