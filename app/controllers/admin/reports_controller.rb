# frozen_string_literal: true

module Admin
  class ReportsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      # Generate reports logic
    end

    # Descarga CSV con todas las piezas de inventario
    # Columnas: ID, SKU, Product Name, Category, Status, Purchase Order, Line, Sale Order, Purchase Cost, Sale Price, Updated
    def inventory_items
      # Eager load para evitar N+1
      items = Inventory.includes(:purchase_order, :sale_order, :product).order(id: :asc)

      require 'csv'
      csv = CSV.generate(headers: true) do |out|
        out << [
          'ID', 'SKU', 'Product Name', 'Category', 'Status', 'Purchase Order', 'Line', 'Sale Order', 'Purchase Cost', 'Sale Price', 'Updated'
        ]

        items.find_each do |inv|
          out << [
            inv.id,
            inv.product&.product_sku,
            inv.product&.product_name,
            inv.product&.category,
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

    # Descarga CSV pieza por pieza solo para inventario con ubicación asignada
    # Columnas: Inventory ID, SKU, Product Name, Category, Status, Location Code, Location Path, Purchase Cost, Selling Price, Updated
    def inventory_items_with_locations
      items = Inventory.includes(:product, :inventory_location)
                       .where.not(inventory_location_id: nil)
                       .order(id: :asc)

      require 'csv'
      csv = CSV.generate(headers: true) do |out|
        out << [
          'Inventory ID', 'SKU', 'Product Name', 'Category', 'Status', 'Location Code', 'Location Path',
          'Purchase Cost', 'Selling Price', 'Updated'
        ]

        items.find_each do |inv|
          out << [
            inv.id,
            inv.product&.product_sku,
            inv.product&.product_name,
            inv.product&.category,
            inv.status,
            inv.inventory_location&.code,
            inv.inventory_location&.full_path,
            inv.purchase_cost,
            inv.selling_price,
            inv.updated_at&.to_date
          ]
        end
      end

      send_data csv,
                filename: "inventory_items_with_locations-#{Time.current.strftime('%Y%m%d-%H%M')}.csv",
                type: 'text/csv'
    end
  end
end
