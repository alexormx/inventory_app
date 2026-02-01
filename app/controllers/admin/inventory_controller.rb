# frozen_string_literal: true

module Admin
  class InventoryController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      # Si no viene :status (p.ej., Enter en búsqueda), conservar el :current_status oculto
      params[:status] ||= params[:current_status]
      @status_filter = params[:status].presence
      @q = params[:q].to_s.strip

      # Base: productos con conteos por estado mediante subconsultas (usando IDs del enum)
      sids = Inventory.statuses # {"available"=>0, ...}
      products = Product
                 .includes(inventories: :purchase_order)
                 .select(
                   "products.*,
         (SELECT COUNT(*) FROM inventories i WHERE i.product_id = products.id AND i.status = #{sids['available']}) AS available_count,
         (SELECT COUNT(*) FROM inventories i WHERE i.product_id = products.id AND i.status = #{sids['reserved']}) AS reserved_count,
         (SELECT COUNT(*) FROM inventories i WHERE i.product_id = products.id AND i.status = #{sids['in_transit']}) AS in_transit_count,
         (SELECT COUNT(*) FROM inventories i WHERE i.product_id = products.id AND i.status = #{sids['sold']}) AS sold_count,
         (SELECT COUNT(*) FROM inventories i WHERE i.product_id = products.id) AS total_count"
                 )

      # Filtro por estatus (si se selecciona uno válido)
      valid_statuses = Inventory.statuses.keys
      if @status_filter.present? && @status_filter != 'all' && valid_statuses.include?(@status_filter)
        products = products.where(
          'EXISTS (SELECT 1 FROM inventories fi WHERE fi.product_id = products.id AND fi.status = ?)',
          Inventory.statuses[@status_filter]
        )
      end

      # Búsqueda por nombre o SKU (case-insensitive, abarca todos los productos)
      if @q.present?
        term = "%#{@q.downcase}%"
        products = products.where('LOWER(products.product_name) LIKE ? OR LOWER(products.product_sku) LIKE ?', term, term)
      end

      # Totales por estado (respetando búsqueda y filtro de status actual)
      # Deriva los IDs de enum
      status_ids = Inventory.statuses
      # Construir un scope de inventories filtrado por los productos actuales
      product_ids = products.pluck(:id)
      inventories_scope = Inventory.where(product_id: product_ids)
      # Si hay filtro de status activo, limitar a ese status
      if @status_filter.present? && @status_filter != 'all' && valid_statuses.include?(@status_filter)
        inventories_scope = inventories_scope.where(status: status_ids[@status_filter])
      end

      status_keys = %w[available reserved in_transit sold returned damaged lost scrap pre_reserved pre_sold marketing]
      # Superiores (globales, no cambian con filtros): conteo global por status
      @inventory_counts_global = {}
      status_keys.each do |key|
        @inventory_counts_global[key.to_sym] = Inventory.where(status: status_ids[key]).count
      end
      # Inferiores (filtrados por q + status)
      @inventory_counts = {}
      status_keys.each do |key|
        @inventory_counts[key.to_sym] = inventories_scope.where(status: status_ids[key]).count
      end

      # Ordenar por prioridad: disponible desc, reservado desc, en tránsito desc, vendido desc, total desc
      @export_products = products
      @products_with_inventory = products
                                 .order('available_count DESC, reserved_count DESC, in_transit_count DESC, sold_count DESC, total_count DESC')
                                 .page(params[:page]).per(10)

      respond_to do |format|
        format.html
        format.csv { send_data csv_for_inventory(@export_products), filename: "inventory-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
        format.any { head :not_acceptable }
      end
    end

    def items
      # Buscar producto por slug/SKU antes que ID para evitar colisiones cuando el slug inicia con números
      @product = Product.find_by_identifier!(params[:id])
      # Consulta directa (evita efectos colaterales del proxy de asociación) y quitar límites ocultos
      status_filter = params[:status].to_s
      valid_statuses = Inventory.statuses.keys
      base_scope = Inventory.where(product_id: @product.id).includes(:inventory_location).unscope(:limit, :offset)
      if status_filter.present? && status_filter != 'all' && valid_statuses.include?(status_filter)
        base_scope = base_scope.where(status: Inventory.statuses[status_filter])
      end
      @inventory_items = base_scope.order(id: :asc)

      # Forzar carga completa a Array antes del render
      @inventory_items = @inventory_items.to_a

      # Turbo Frames: usar el id de frame esperado (enviado por Turbo en el header)
      expected_frame_id = request.headers['Turbo-Frame']
      respond_to do |format|
        format.turbo_stream do
          # Responder con el frame correcto si Turbo lo espera
          render partial: 'admin/inventory/items', locals: { product: @product, items: @inventory_items, frame_id: expected_frame_id }
        end
        format.html do
          # Fallback: renderizar la misma partial dentro del layout normal
          render partial: 'admin/inventory/items', locals: { product: @product, items: @inventory_items, frame_id: expected_frame_id }
        end
      end
    end

    def edit_status
      @item = Inventory.find(params[:id])
      render partial: 'admin/inventory/edit_status_form', locals: { item: @item }
    end

    def update_status
      @item = Inventory.find(params[:id])

      if @item.status != 'sold' && Inventory.statuses.keys.include?(params[:status])
        @item.update(status: params[:status], status_changed_at: Time.current)
        @product = @item.product

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("inventory_status_#{@item.id}", partial: 'admin/inventory/status_badge', locals: { item: @item }),
              turbo_stream.replace("inventory-summary-#{@product.id}", partial: 'admin/inventory/summary', locals: { product: @product })
            ]
          end
          format.html do
            redirect_to admin_inventory_index_path, notice: 'Status updated'
          end
        end
      else
        redirect_to admin_inventory_index_path, alert: 'Status could not be updated'
      end
    end

    # Para el botón Cancelar
    def cancel_edit_status
      @item = Inventory.find(params[:id])
      render partial: 'admin/inventory/status_badge', locals: { item: @item }
    end

    # GET /admin/inventory/unlocated - Inventario sin ubicación asignada
    def unlocated
      # Solo items available y reserved sin ubicación
      base_scope = Inventory.where(status: %i[available reserved], inventory_location_id: nil)

      # Agrupar por producto con conteos
      @products_data = base_scope.group(:product_id).count

      product_ids = @products_data.keys

      # Base de productos
      products_scope = Product.where(id: product_ids)

      # Filtro de búsqueda
      @q = params[:q].to_s.strip
      if @q.present?
        term = "%#{@q.downcase}%"
        products_scope = products_scope.where('LOWER(product_name) LIKE ? OR LOWER(product_sku) LIKE ?', term, term)
      end

      # Ordenación
      @sort = params[:sort].presence || 'name'
      case @sort
      when 'count_desc'
        # Ordenar por cantidad sin ubicar (descendente)
        sorted_ids = @products_data.sort_by { |_id, count| -count }.map(&:first)
        # Filtrar por IDs de productos que coincidan con la búsqueda
        filtered_ids = products_scope.pluck(:id)
        sorted_ids = sorted_ids & filtered_ids
        # Paginar manualmente
        page_num = (params[:page] || 1).to_i
        per_page = 20
        offset = (page_num - 1) * per_page
        paged_ids = sorted_ids[offset, per_page] || []
        @products = Product.where(id: paged_ids).index_by(&:id)
        @products = paged_ids.map { |id| @products[id] }.compact
        @total_products = sorted_ids.size
        @current_page = page_num
        @total_pages = (sorted_ids.size.to_f / per_page).ceil
      when 'count_asc'
        sorted_ids = @products_data.sort_by { |_id, count| count }.map(&:first)
        filtered_ids = products_scope.pluck(:id)
        sorted_ids = sorted_ids & filtered_ids
        page_num = (params[:page] || 1).to_i
        per_page = 20
        offset = (page_num - 1) * per_page
        paged_ids = sorted_ids[offset, per_page] || []
        @products = Product.where(id: paged_ids).index_by(&:id)
        @products = paged_ids.map { |id| @products[id] }.compact
        @total_products = sorted_ids.size
        @current_page = page_num
        @total_pages = (sorted_ids.size.to_f / per_page).ceil
      else
        # Por nombre (default)
        @products = products_scope.order(:product_name).page(params[:page]).per(20)
        @total_products = products_scope.count
        @current_page = @products.current_page
        @total_pages = @products.total_pages
      end

      @total_unlocated = base_scope.count
      @location_options = InventoryLocation.active.nested_options
    end

    # GET /admin/inventory/unlocated_items/:product_id - Detalle de piezas sin ubicar (AJAX)
    def unlocated_items
      @product = Product.find(params[:product_id])
      @items = Inventory.includes(:purchase_order)
                        .where(product_id: @product.id, status: %i[available reserved], inventory_location_id: nil)
                        .order(:created_at)
                        .limit(50)

      render partial: 'admin/inventory/unlocated_items_detail', locals: { items: @items, product: @product }
    end

    # POST /admin/inventory/bulk_assign_location - Asignar ubicación masivamente
    def bulk_assign_location
      location_id = params[:inventory_location_id].to_i
      assignments = params[:assignments] || {}

      @location = InventoryLocation.find_by(id: location_id)
      unless @location
        redirect_to admin_inventory_unlocated_path, alert: 'Ubicación no encontrada'
        return
      end

      total_assigned = 0
      errors = []

      ActiveRecord::Base.transaction do
        assignments.each do |product_id, quantity|
          qty = quantity.to_i
          next if qty <= 0

          # FIFO: asignar los items más antiguos primero
          items = Inventory.where(
            product_id: product_id,
            status: %i[available reserved],
            inventory_location_id: nil
          ).order(:created_at).limit(qty)

          assigned = items.update_all(
            inventory_location_id: @location.id,
            updated_at: Time.current
          )
          total_assigned += assigned
        end
      end

      if total_assigned > 0
        respond_to do |format|
          format.html { redirect_to admin_inventory_unlocated_path, notice: "#{total_assigned} piezas asignadas a #{@location.code}" }
          format.turbo_stream {
            flash.now[:notice] = "#{total_assigned} piezas asignadas a #{@location.code}"
            # Re-cargar datos para actualizar la vista
            base_scope = Inventory.where(status: %i[available reserved], inventory_location_id: nil)
            @products_data = base_scope.group(:product_id)
                                       .select('product_id, COUNT(*) as unlocated_count')
                                       .index_by(&:product_id)
            product_ids = @products_data.keys
            @products = Product.where(id: product_ids).order(:product_name)
            @total_unlocated = base_scope.count
            @location_options = InventoryLocation.active.nested_options
          }
        end
      else
        redirect_to admin_inventory_unlocated_path, alert: 'No se asignó ninguna pieza'
      end
    end

    private

    def inventory_params
      params.expect(inventory: %i[status status_changed_at])
    end

    def csv_for_inventory(relation)
      require 'csv'
      CSV.generate(headers: true) do |csv|
        csv << [
          'Product ID',
          'SKU',
          'Name',
          'Available',
          'Reserved',
          'In Transit',
          'Sold',
          'Total',
          'Average Purchase Cost',
          'Inventory Value (MXN)'
        ]
        relation.find_each do |p|
          csv << [
            p.id,
            p.product_sku,
            p.product_name,
            p.attributes['available_count'].to_i,
            p.attributes['reserved_count'].to_i,
            p.attributes['in_transit_count'].to_i,
            p.attributes['sold_count'].to_i,
            p.attributes['total_count'].to_i,
            p.average_purchase_cost || 0,
            p.current_inventory_value || 0
          ]
        end
      end
    end

    # XLSX export removed
  end
end
