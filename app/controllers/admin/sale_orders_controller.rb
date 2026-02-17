# frozen_string_literal: true

# app/controllers/admin/sale_orders_controller.rb
module Admin
  class SaleOrdersController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_sale_order, only: %i[show edit update destroy summary cancel prepare ship deliver]
    before_action :load_counts, only: [:index]

    PER_PAGE = 20

    def index
      params[:status] ||= params[:current_status]
      @status_filter = params[:status].presence
      @q = params[:q].to_s.strip
      @due_filter = %w[1 true yes on].include?(params[:due].to_s)

      scope = build_base_scope
      scope = apply_sorting(scope)
      scope = apply_filters(scope)

      @export_sale_orders = scope
      @sale_orders = scope.page(params[:page]).per(PER_PAGE)

      build_status_counts(scope)

      respond_to do |format|
        format.html
        format.csv { send_data csv_for_sale_orders(@export_sale_orders), filename: "sale_orders-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
        format.any { head :not_acceptable }
      end
    end

    def show; end

    def new
      @sale_order = SaleOrder.new(order_date: Time.zone.today)
    end

    def edit; end

    def create
      @sale_order = SaleOrder.new(sale_order_params)
      if @sale_order.save
        @sale_order.update_status_if_fully_paid!
        redirect_to admin_sale_order_path(@sale_order), notice: 'Orden de venta creada.'
      else
        Rails.logger.error(@sale_order.errors.full_messages)
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @sale_order = SaleOrder.find(params[:id])
      if @sale_order.update(sale_order_params)
        @sale_order.update_status_if_fully_paid!
        redirect_to admin_sale_order_path(@sale_order), notice: 'Orden de venta actualizada.'
      else
        flash.now[:alert] = 'Hubo errores al guardar la orden de venta.'
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      failed_item = e.record
      error_msg = failed_item&.errors&.full_messages&.join(', ') ||
                  'No se puede eliminar una línea con inventario vendido'
      flash.now[:alert] = error_msg
      @sale_order.reload
      render :edit, status: :unprocessable_entity
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error("[SaleOrdersController#update] StatementInvalid al actualizar SO #{@sale_order&.id}: #{e.class} - #{e.message}")
      flash.now[:alert] = 'No se pudo eliminar la pieza porque tiene registros relacionados de auditoría/asignación. Refresca la orden e intenta nuevamente.'
      @sale_order.reload
      render :edit, status: :unprocessable_entity
    rescue ActiveModel::UnknownAttributeError => e
      Rails.logger.error("[SaleOrdersController#update] UnknownAttributeError al actualizar SO #{@sale_order&.id}: #{e.class} - #{e.message}")
      flash.now[:alert] = 'No se pudo eliminar la pieza por una discrepancia de esquema. Verifica migraciones pendientes en producción.'
      @sale_order.reload
      render :edit, status: :unprocessable_entity
    end

    def destroy
      redirect_to admin_sale_order_path(@sale_order),
                  alert: 'La eliminación está deshabilitada. Usa Cancelar para liberar inventario.'
    end

    def cancel
      SaleOrders::CancelOrderService.new(@sale_order).call
      redirect_to admin_sale_order_path(@sale_order),
                  notice: 'Orden cancelada exitosamente. Inventarios liberados y disponibles.'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_sale_order_path(@sale_order),
                  alert: "No se pudo cancelar la orden: #{e.message}"
    end

    def summary
      @order = @sale_order
      render 'orders/summary'
    end

    # GET /admin/sale_orders/:id/prepare
    # Muestra la vista de picking: piezas agrupadas por ubicación para preparar el paquete.
    # Transiciona Confirmed → Preparing y auto-crea shipment si no existe.
    def prepare
      unless %w[Confirmed Preparing].include?(@sale_order.status)
        redirect_to admin_sale_order_path(@sale_order),
                    alert: "Solo se puede preparar una orden Confirmada. Estado actual: #{@sale_order.status}" and return
      end

      # Verificar que todas las piezas de inventario estén en bodega (no en tránsito del proveedor)
      in_transit_pieces = @sale_order.inventories.where(status: %i[pre_reserved pre_sold in_transit])
      if in_transit_pieces.exists?
        redirect_to admin_sale_order_path(@sale_order),
                    alert: "No se puede preparar: #{in_transit_pieces.count} pieza(s) aún en tránsito del proveedor. Espera a que lleguen al almacén." and return
      end

      # Auto-crear shipment en pending si no existe
      if @sale_order.shipment.blank?
        order_base = @sale_order.order_date || Time.zone.today
        @sale_order.create_shipment!(
          carrier: 'Por asignar',
          estimated_delivery: order_base + 7,
          status: :pending
        )
        @sale_order.reload
      end

      # Transicionar a Preparing si está en Confirmed
      @sale_order.update!(status: 'Preparing') if @sale_order.status == 'Confirmed'

      # Cargar inventarios con ubicaciones para la vista de picking
      @inventories = @sale_order.inventories
                                .includes(:product, :inventory_location)
                                .where(status: %i[reserved sold pre_reserved pre_sold])
                                .order(:inventory_location_id, :id)

      # Agrupar por ubicación para la vista
      @grouped = @inventories.group_by { |inv| inv.inventory_location&.full_path || 'Sin ubicación' }
    end

    # POST /admin/sale_orders/:id/ship
    # Marca el envío como shipped y transiciona Preparing → In Transit
    def ship
      unless @sale_order.status == 'Preparing'
        redirect_to admin_sale_order_path(@sale_order),
                    alert: "Solo se puede despachar una orden en Preparación. Estado actual: #{@sale_order.status}" and return
      end

      shipment = @sale_order.shipment
      redirect_to admin_sale_order_path(@sale_order), alert: 'No hay envío asignado.' and return unless shipment

      # Actualizar tracking y carrier si se proporcionan
      ship_attrs = {}
      ship_attrs[:tracking_number] = params[:tracking_number] if params[:tracking_number].present?
      ship_attrs[:carrier] = params[:carrier] if params[:carrier].present?
      ship_attrs[:status] = :shipped

      if shipment.update(ship_attrs)
        # El callback sync_sale_order_status_from_shipment se encarga de: Preparing → In Transit
        @sale_order.reload
        redirect_to admin_sale_order_path(@sale_order),
                    notice: '📦 Paquete despachado. Orden en tránsito.'
      else
        redirect_to prepare_admin_sale_order_path(@sale_order),
                    alert: "Error al despachar: #{shipment.errors.full_messages.join(', ')}"
      end
    end

    # POST /admin/sale_orders/:id/deliver
    # Marca el envío como delivered y transiciona In Transit → Delivered
    def deliver
      unless @sale_order.status == 'In Transit'
        redirect_to admin_sale_order_path(@sale_order),
                    alert: "Solo se puede marcar como entregada una orden en tránsito. Estado actual: #{@sale_order.status}" and return
      end

      shipment = @sale_order.shipment
      redirect_to admin_sale_order_path(@sale_order), alert: 'No hay envío asignado.' and return unless shipment

      if shipment.update(status: :delivered)
        # El callback sync_sale_order_status_from_shipment se encarga de: In Transit → Delivered
        @sale_order.reload
        redirect_to admin_sale_order_path(@sale_order),
                    notice: '✅ Orden marcada como entregada.'
      else
        redirect_to admin_sale_order_path(@sale_order),
                    alert: "Error al marcar como entregada: #{shipment.errors.full_messages.join(', ')}"
      end
    end

    private

    def set_sale_order
      @sale_order = SaleOrder.find(params[:id])
    end

    def sale_order_params
      params.expect(
        sale_order: [:user_id, :order_date, :subtotal, :tax_rate,
                     :total_tax, :total_order_value, :discount,
                     :status, :notes,
                     :credit_override, :credit_terms,
                     { sale_order_items_attributes: [%i[
                       id product_id quantity unit_cost unit_discount
                       unit_final_price total_line_cost total_line_volume
                       total_line_weight _destroy
                     ]] }]
      )
    end

    def load_counts
      @load_counts ||= SaleOrder.group(:status).count
    end

    # --- Index helpers (extracted for readability) ---

    def build_base_scope
      items_sql   = '(SELECT COALESCE(SUM(quantity),0) FROM sale_order_items soi WHERE soi.sale_order_id = sale_orders.id) AS items_count'
      paid_sql    = "(SELECT COALESCE(SUM(amount),0) FROM payments p WHERE p.sale_order_id = sale_orders.id AND p.status = 'Completed') AS total_paid_value"
      balance_sql = "(sale_orders.total_order_value - (SELECT COALESCE(SUM(amount),0) FROM payments p2 WHERE p2.sale_order_id = sale_orders.id AND p2.status = 'Completed')) AS balance_due_value"

      SaleOrder.joins(:user).includes(:user)
               .select('sale_orders.*', items_sql, paid_sql, balance_sql)
    end

    def apply_sorting(scope)
      sort = params[:sort].presence
      dir  = params[:dir].to_s.downcase == 'asc' ? 'ASC' : 'DESC'
      sort_map = {
        'date' => 'sale_orders.order_date',
        'created' => 'sale_orders.created_at',
        'customer' => 'users.name',
        'total_mxn' => 'sale_orders.total_order_value',
        'items' => 'items_count',
        'paid' => 'total_paid_value',
        'balance' => 'balance_due_value'
      }

      if sort_map.key?(sort)
        scope.order(Arel.sql("#{sort_map[sort]} #{dir}"))
      else
        scope.order(created_at: :desc)
      end
    end

    def apply_filters(scope)
      scope = scope.where(status: @status_filter) if @status_filter.present? && @status_filter != 'all'

      if @due_filter
        balance_expr = "sale_orders.total_order_value - (SELECT COALESCE(SUM(amount),0) FROM payments p2 WHERE p2.sale_order_id = sale_orders.id AND p2.status = 'Completed')"
        scope = scope.where(Arel.sql("#{balance_expr} > 0"))
      end

      scope = apply_search(scope) if @q.present?
      scope
    end

    def apply_search(scope)
      adapter  = ActiveRecord::Base.connection.adapter_name.downcase
      postgres = adapter.include?('postgres')
      id_cast  = postgres ? 'sale_orders.id::text' : 'CAST(sale_orders.id AS TEXT)'
      name_cond = postgres ? 'users.name ILIKE ?' : 'LOWER(users.name) LIKE ?'
      term = postgres ? "%#{@q}%" : "%#{@q.downcase}%"

      if (m = @q.match(/\A#?(\d+)\z/))
        scope.where(["sale_orders.id = ? OR #{name_cond}", m[1].to_i, term])
      else
        scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
      end
    end

    def build_status_counts(_filtered_scope)
      statuses = %w[Pending Confirmed Preparing Shipped Delivered Canceled]

      # Global counts (unaffected by filters)
      global_grouped = SaleOrder.group(:status).count
      @counts_global = statuses.index_with { |s| global_grouped[s] || 0 }

      # Filtered counts (respecting search + status + due filters)
      counts_scope = SaleOrder.joins(:user)
      counts_scope = apply_search(counts_scope) if @q.present?
      counts_scope = counts_scope.where(status: @status_filter) if @status_filter.present? && @status_filter != 'all'
      filtered_grouped = counts_scope.group(:status).count
      @counts = statuses.index_with { |s| filtered_grouped[s] || 0 }
    end

    def csv_for_sale_orders(relation)
      require 'csv'
      CSV.generate(headers: true) do |csv|
        csv << ['ID', 'Customer', 'Order Date', 'Status', 'Items', 'Total', 'Pagado', 'Adeudo', 'Discount']
        relation.each do |so|
          csv << [
            so.id, so.user&.name, so.order_date, so.status,
            so.attributes['items_count'].to_i, so.total_order_value,
            so.attributes['total_paid_value'].to_d,
            so.attributes['balance_due_value'].to_d, so.discount
          ]
        end
      end
    end
  end
end
