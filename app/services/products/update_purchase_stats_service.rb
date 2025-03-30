  # app/services/update_purchase_stats_service.rb
 module Products
  class UpdatePurchaseStatsService
    def initialize(product)
      @product = product
    end

    def call
      puts "Service called for: #{@product.product_name}"
      update_purchase_data
      update_derived_metrics
      puts "SThis was updaed: #{@product} - Purchase data updated"
      @product.save!
    end

    private

    def update_purchase_data
      items = @product.purchase_order_items.joins(:purchase_order)
      @product.total_purchase_quantity = items.sum(:quantity)
      @product.total_purchase_value = items.sum("quantity * unit_cost")
      @product.average_purchase_cost = @product.total_purchase_quantity > 0 ? @product.total_purchase_value / @product.total_purchase_quantity : 0.0
      
      @product.stock_quantity = @product.total_purchase_quantity - @product.total_sales_quantity


      last_item = items.order("purchase_orders.order_date DESC").first
      if last_item
        @product.last_purchase_cost = last_item.unit_cost
        @product.last_purchase_date = last_item.purchase_order.order_date
        @product.last_supplier = last_item.purchase_order.user
      end

      @product.total_purchase_order = items.map(&:purchase_order_id).uniq.count
    end

    def update_derived_metrics
      @product.current_profit = @product.total_sales_value - @product.total_purchase_value
      @product.current_inventory_value = @product.average_purchase_cost * @product.stock_quantity
      remaining_stock = @product.total_purchase_quantity - @product.total_sales_quantity
      @product.total_purchase_value = remaining_stock * @product.average_purchase_cost
      @product.projected_sales_value = remaining_stock * @product.selling_price
      @product.projected_profit = @product.current_profit + @product.projected_sales_value
    end
  end
end
