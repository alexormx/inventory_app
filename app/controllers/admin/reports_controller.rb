class Admin::ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Generate reports logic
  end

  # Reporte de cancelaciones: por rango y cliente opcional
  def cancellations
    from = params[:from].presence && Time.zone.parse(params[:from])
    to   = params[:to].presence && Time.zone.parse(params[:to])
    user_id = params[:user_id].presence

    scope = CanceledOrderItem.includes(:product, :sale_order => :user)
    scope = scope.where('canceled_at >= ?', from) if from
    scope = scope.where('canceled_at <= ?', to) if to
    scope = scope.where(sale_order_id: SaleOrder.where(user_id: user_id).select(:id)) if user_id

    respond_to do |format|
      format.html do
        @items = scope.order(canceled_at: :desc).page(params[:page]).per(50)
        # Agregados simples por cliente
        @by_customer = scope.group('sale_orders.user_id').joins(:sale_order)
                            .sum(:canceled_quantity)
      end
      format.csv do
        require 'csv'
        csv = CSV.generate(headers: true) do |out|
          out << ["Sale Order","Customer","Product SKU","Product Name","Canceled Qty","Unit Price at Cancel","Reason","Canceled At"]
          scope.find_each do |it|
            out << [
              it.sale_order_id,
              it.sale_order&.user&.name,
              it.product&.product_sku,
              it.product&.product_name,
              it.canceled_quantity,
              it.sale_price_at_cancellation,
              it.cancellation_reason,
              it.canceled_at&.strftime('%F %T')
            ]
          end
        end
        send_data csv, filename: "cancellations-#{Time.current.strftime('%Y%m%d-%H%M')}.csv", type: 'text/csv'
      end
    end
  end

  # Descarga CSV con todas las piezas de inventario
  # Columnas: ID, SKU, Product Name, Status, Purchase Order, Line, Sale Order, Purchase Cost, Sale Price, Updated
  def inventory_items
    # Eager load para evitar N+1
    items = Inventory.includes(:purchase_order, :sale_order, :product).order(id: :asc)

    require 'csv'
    csv = CSV.generate(headers: true) do |out|
      out << [
        "ID", "SKU", "Product Name", "Status", "Purchase Order", "Line", "Sale Order", "Purchase Cost", "Sale Price", "Updated"
      ]

      items.find_each do |inv|
        out << [
          inv.id,
          inv.product&.product_sku,
          inv.product&.product_name,
          inv.status,
          inv.purchase_order_id,
          inv.purchase_order_item_id,
          inv.sale_order_id,
          inv.purchase_cost,
          inv.sold_price,
          inv.updated_at&.to_date
        ]
      end
    end

    send_data csv,
              filename: "inventory_items-#{Time.current.strftime('%Y%m%d-%H%M')}.csv",
              type: 'text/csv'
  end
end
