class Admin::InventoryController < ApplicationController
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
    if @status_filter.present? && @status_filter != "all" && valid_statuses.include?(@status_filter)
      products = products.where(
        "EXISTS (SELECT 1 FROM inventories fi WHERE fi.product_id = products.id AND fi.status = ?)",
        Inventory.statuses[@status_filter]
      )
    end

    # Búsqueda por nombre o SKU (case-insensitive, abarca todos los productos)
    if @q.present?
      term = "%#{@q.downcase}%"
      products = products.where("LOWER(products.product_name) LIKE ? OR LOWER(products.product_sku) LIKE ?", term, term)
    end

    # Totales por estado (respetando búsqueda y filtro de status actual)
    # Deriva los IDs de enum
    status_ids = Inventory.statuses
    # Construir un scope de inventories filtrado por los productos actuales
  product_ids = products.pluck(:id)
  inventories_scope = Inventory.where(product_id: product_ids)
    # Si hay filtro de status activo, limitar a ese status
    if @status_filter.present? && @status_filter != "all" && valid_statuses.include?(@status_filter)
      inventories_scope = inventories_scope.where(status: status_ids[@status_filter])
    end

    status_keys = %w[available reserved in_transit sold returned damaged lost scrap]
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
      .order("available_count DESC, reserved_count DESC, in_transit_count DESC, sold_count DESC, total_count DESC")
      .page(params[:page]).per(10)

    respond_to do |format|
      format.html
      format.csv  { send_data csv_for_inventory(@export_products), filename: "inventory-#{Time.current.strftime('%Y%m%d-%H%M')}.csv" }
      format.xlsx { render xlsx: "index", filename: "inventory-#{Time.current.strftime('%Y%m%d-%H%M')}.xlsx" }
    end
  end

  def items
    @product = Product.find_by_identifier!(params[:id])
  @inventory_items = @product.inventories.includes(:purchase_order).order(id: :asc)

  # Turbo Frames: usar el id de frame esperado (enviado por Turbo en el header)
    expected_frame_id = request.headers["Turbo-Frame"]
    respond_to do |format|
      format.turbo_stream do
        # Responder con el frame correcto si Turbo lo espera
        render partial: "admin/inventory/items", locals: { product: @product, items: @inventory_items, frame_id: expected_frame_id }
      end
      format.html do
        # Fallback: renderizar la misma partial dentro del layout normal
        render partial: "admin/inventory/items", locals: { product: @product, items: @inventory_items, frame_id: expected_frame_id }
      end
    end
  end

  def edit_status
    @item = Inventory.find(params[:id])
    render partial: "admin/inventory/edit_status_form", locals: { item: @item }
  end
  
  def update_status
    @item = Inventory.find(params[:id])

    if @item.status != "sold" && Inventory.statuses.keys.include?(params[:status])
      @item.update(status: params[:status], status_changed_at: Time.current)
      @product = @item.product
  
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("inventory_status_#{@item.id}", partial: "admin/inventory/status_badge", locals: { item: @item }),
            turbo_stream.replace("inventory-summary-#{@product.id}", partial: "admin/inventory/summary", locals: { product: @product })
          ]
        end
        format.html do
          redirect_to admin_inventory_index_path, notice: "Status updated"
        end
      end
    else
      redirect_to admin_inventory_index_path, alert: "Status could not be updated"
    end
  end

  # Para el botón Cancelar
  def cancel_edit_status
    @item = Inventory.find(params[:id])
    render partial: "admin/inventory/status_badge", locals: { item: @item }
  end

  private
  def inventory_params
    params.require(:inventory).permit(:status, :status_changed_at)
  end

  def csv_for_inventory(relation)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << ["Product ID", "SKU", "Name", "Available", "Reserved", "In Transit", "Sold", "Total"]
      relation.find_each do |p|
        csv << [
          p.id, p.product_sku, p.product_name,
          p.attributes["available_count"].to_i,
          p.attributes["reserved_count"].to_i,
          p.attributes["in_transit_count"].to_i,
          p.attributes["sold_count"].to_i,
          p.attributes["total_count"].to_i
        ]
      end
    end
  end
end
