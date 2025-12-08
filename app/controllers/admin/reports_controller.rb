# frozen_string_literal: true

module Admin
  class ReportsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      # Generate reports logic
    end

    # Descarga CSV con todas las piezas de inventario
    # Columnas: ID, SKU, Product Name, Status, Purchase Order, Line, Sale Order, Purchase Cost, Sale Price, Updated
    def inventory_items
      # Eager load para evitar N+1
      items = Inventory.includes(:purchase_order, :sale_order, :product).order(id: :asc)

      require 'csv'
      csv = CSV.generate(headers: true) do |out|
        out << [
          'ID', 'SKU', 'Product Name', 'Status', 'Purchase Order', 'Line', 'Sale Order', 'Purchase Cost', 'Sale Price', 'Updated'
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
end
