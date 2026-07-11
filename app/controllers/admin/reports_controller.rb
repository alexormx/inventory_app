# frozen_string_literal: true

module Admin
  class ReportsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      # Generate reports logic
    end

    # Órdenes con piezas reservadas hace mucho tiempo que aún tienen ubicación
    # física (reserved/pre_reserved). Son oportunidad de venta: se puede cancelar
    # la reserva pieza por pieza para ofrecerlas a otros clientes. Agrupado por orden.
    def stale_reservations
      @min_days = params[:min_days].presence&.to_i || 90
      @min_days = 0 if @min_days.negative?
      cutoff = @min_days.days.ago

      pieces = Inventory
               .includes(:product, :inventory_location, sale_order: :user)
               .where(status: %i[reserved pre_reserved])
               .where.not(inventory_location_id: nil)
               .where.not(sale_order_id: nil)
               .where(status_changed_at: ..cutoff)
               .order(:sale_order_id, status_changed_at: :asc)
               .to_a

      grouped = pieces.group_by(&:sale_order_id)
      # Órdenes con la reserva más antigua primero: mayor oportunidad de liberar.
      @groups = grouped.sort_by { |_id, list| list.map(&:status_changed_at).min }

      @total_orders = grouped.size
      @total_pieces = pieces.size
      @total_value  = pieces.sum { |inv| piece_value(inv) }
    end

    # Cancela la reserva de UNA pieza: la regresa a 'available'. Los callbacks del
    # modelo Inventory limpian sale_order_id/sale_order_item_id/sold_price y
    # reasignan preventas pendientes, igual que al cancelar una orden completa.
    def cancel_reservation
      inv = Inventory.find(params[:inventory_id])
      redirect_params = { min_days: params[:min_days].presence }

      unless %w[reserved pre_reserved].include?(inv.status)
        return redirect_to stale_reservations_admin_reports_path(redirect_params),
                           alert: "La pieza ##{inv.id} ya no está reservada."
      end

      order_id = inv.sale_order_id
      inv.update!(status: :available)

      redirect_to stale_reservations_admin_reports_path(redirect_params),
                  notice: "Reserva de la pieza ##{inv.id} (orden #{order_id}) cancelada. La pieza quedó disponible."
    rescue ActiveRecord::RecordNotFound
      redirect_to stale_reservations_admin_reports_path(min_days: params[:min_days].presence),
                  alert: 'Pieza no encontrada.'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to stale_reservations_admin_reports_path(min_days: params[:min_days].presence),
                  alert: "No se pudo cancelar la reserva: #{e.message}"
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

    private

    # Valor de oportunidad de una pieza: precio individual si aplica, si no el del producto.
    def piece_value(inv)
      inv.selling_price || inv.product&.selling_price || 0
    end
  end
end
