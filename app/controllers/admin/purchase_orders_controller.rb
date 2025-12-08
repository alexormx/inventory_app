# frozen_string_literal: true

module Admin
  class PurchaseOrdersController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_purchase_order, only: %i[show edit update confirm_receipt destroy summary]
    before_action :load_counts, only: [:index]

    PER_PAGE = 20

    def index
      params[:status] ||= params[:current_status]
      @status_filter = params[:status].presence
      @q = params[:q].to_s.strip

      scope = PurchaseOrder.joins(:user).includes(:user)
      # Units per order (sum of item quantities) as items_count via subquery
      scope = scope.select('purchase_orders.*',
                           '(SELECT COALESCE(SUM(quantity),0) FROM purchase_order_items poi WHERE poi.purchase_order_id = purchase_orders.id) AS items_count')
      # Sorting
      sort = params[:sort].presence
      dir  = params[:dir].to_s.downcase == 'asc' ? 'asc' : 'desc'
      sort_map = {
        'supplier' => 'users.name',
        'date' => 'purchase_orders.order_date',
        'expected' => 'purchase_orders.expected_delivery_date',
        'total_mxn' => 'purchase_orders.total_cost_mxn',
        'items' => 'items_count',
        'created' => 'purchase_orders.created_at'
      }
      scope = if sort_map.key?(sort)
                scope.order(Arel.sql("#{sort_map[sort]} #{dir.upcase}"))
              else
                scope.order(created_at: :desc)
              end
      scope = scope.where(status: @status_filter) if @status_filter.present? && @status_filter != 'all'
      if @q.present?
        adapter = ActiveRecord::Base.connection.adapter_name.downcase
        id_cast = adapter.include?('postgres') ? 'purchase_orders.id::text' : 'CAST(purchase_orders.id AS TEXT)'
        name_cond = adapter.include?('postgres') ? 'users.name ILIKE ?' : 'LOWER(users.name) LIKE ?'
        term = adapter.include?('postgres') ? "%#{@q}%" : "%#{@q.downcase}%"
        if (m = @q.match(/\A#?(\d+)\z/))
          # Búsqueda directa por ID exacto (permite prefijo opcional #)
          exact_id = m[1].to_i
          scope = scope.where(["purchase_orders.id = ? OR #{name_cond}", exact_id, term])
        else
          scope = scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
        end
      end
      # Dataset para exportación (sin paginar)
      @export_purchase_orders = scope
      @purchase_orders = scope.page(params[:page]).per(PER_PAGE)

      counts_scope = PurchaseOrder.joins(:user)
      if @q.present?
        adapter = ActiveRecord::Base.connection.adapter_name.downcase
        id_cast = adapter.include?('postgres') ? 'purchase_orders.id::text' : 'CAST(purchase_orders.id AS TEXT)'
        name_cond = adapter.include?('postgres') ? 'users.name ILIKE ?' : 'LOWER(users.name) LIKE ?'
        term = adapter.include?('postgres') ? "%#{@q}%" : "%#{@q.downcase}%"
        if (m = @q.match(/\A#?(\d+)\z/))
          exact_id = m[1].to_i
          counts_scope = counts_scope.where(["purchase_orders.id = ? OR #{name_cond}", exact_id, term])
        else
          counts_scope = counts_scope.where(["#{id_cast} LIKE ? OR #{name_cond}", term, term])
        end
      end
      statuses = ['Pending', 'In Transit', 'Delivered', 'Canceled']
      # Superiores (globales)
      @counts_global = statuses.index_with { |s| PurchaseOrder.where(status: s).count }
      # Inferiores (filtrados por q y status)
      filtered = counts_scope
      filtered = filtered.where(status: @status_filter) if @status_filter.present? && @status_filter != 'all'
      @counts = statuses.index_with { |s| filtered.where(status: s).count }
      respond_to do |format|
        format.html
        format.csv { send_data csv_for_purchase_orders(@export_purchase_orders), filename: "purchase_orders-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
        format.any  { head :not_acceptable }
      end
    end

    def show; end

    def summary
      # Vista compacta solo lectura para compartir totales y líneas esenciales
      render :summary
    end

    def new
      @purchase_order = PurchaseOrder.new(order_date: Time.zone.today)
    end

    def edit; end

    def create
      @purchase_order = PurchaseOrder.new(purchase_order_params)

      if @purchase_order.save
        redirect_to admin_purchase_orders_path, notice: 'Purchase order created successfully.'
      else
        flash.now[:alert] = @purchase_order.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @purchase_order.update(purchase_order_params)
        redirect_to admin_purchase_orders_path, notice: 'Purchase order updated successfully.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @purchase_order = PurchaseOrder.find(params[:id])

      if @purchase_order.destroy
        redirect_to admin_purchase_orders_path, notice: 'Purchase order eliminada.'
      else
        redirect_to admin_purchase_order_path(@purchase_order),
                    alert: @purchase_order.errors.full_messages.to_sentence.presence || 'No se pudo eliminar.'
      end
    end

    def confirm_receipt
      if @purchase_order.status == 'In Transit'
        # Guardar product_ids antes de hacer update_all
        product_ids = Inventory.where(purchase_order_id: @purchase_order.id)
                               .in_transit
                               .pluck(:product_id)
                               .uniq

        # Marcar inventario como disponible
        Inventory.where(purchase_order_id: @purchase_order.id).in_transit.update_all(
          status: :available,
          updated_at: Time.current,
          status_changed_at: Time.current
        )
        @purchase_order.update!(status: 'Delivered')

        # Asignar inventario recibido a preorders pendientes
        if product_ids.present?
          Rails.logger.info "[PurchaseOrders] Allocating received inventory to preorders for #{product_ids.count} products"
          Preorders::PreorderAllocator.batch_allocate(product_ids)
        end

        flash[:notice] = 'Recepción confirmada. Inventario actualizado.'
      else
        flash[:alert] = "Solo se pueden confirmar órdenes 'In Transit'."
      end
      redirect_to admin_purchase_order_path(@purchase_order)
    end

    private

    def set_purchase_order
      @purchase_order = PurchaseOrder.includes(:purchase_order_items).find(params[:id])
    end

    def purchase_order_params
      params.require(:purchase_order).permit(
        :user_id, :order_date, :expected_delivery_date,
        :tax_cost, :currency, :shipping_cost,
        :other_cost, :discount, :status, :notes,
        :actual_delivery_date, :exchange_rate,
        :subtotal, :total_order_cost, :total_cost_mxn, :total_volume, :total_weight,
        purchase_order_items_attributes: [
          :id, :product_id, :quantity, :unit_cost,
          :unit_additional_cost, :unit_compose_cost, :unit_compose_cost_in_mxn,
          :total_line_cost, :total_line_volume, :total_line_weight, :total_line_cost_in_mxn, :_destroy
        ]
      )
    end

    def load_counts
      @load_counts ||= PurchaseOrder.group(:status).count
    end

    def csv_for_purchase_orders(relation)
      require 'csv'
      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', 'Supplier', 'Order Date', 'Expected Delivery', 'Status',
          'Items', 'Currency', 'Total Cost', 'Total Cost MXN', 'Total Weight', 'Total Volume'
        ]
        relation.each do |po|
          csv << [
            po.id,
            po.user&.name,
            po.order_date,
            po.expected_delivery_date,
            po.status,
            po.attributes['items_count'].to_i,
            po.currency,
            po.total_order_cost,
            po.total_cost_mxn,
            po.total_weight,
            po.total_volume
          ]
        end
      end
    end

    # XLSX export removed
  end
end
