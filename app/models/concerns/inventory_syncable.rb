# app/models/concerns/inventory_syncable.rb
module InventorySyncable
  extend ActiveSupport::Concern

  included do
    # Puede incluir validaciones o callbacks compartidos si lo deseas
  end

  # Método principal que sincroniza el inventario con base en la cantidad y estado
  def sync_inventory_records
    return unless product && parent_order&.persisted?

    is_sale = respond_to?(:sale_order)
    is_purchase = respond_to?(:purchase_order)

    # Busca ítems ya asignados a esta orden
    assigned_items = Inventory.where(product_id: product.id)
    assigned_items = assigned_items.where(sale_order_id: sale_order_id) if is_sale
    assigned_items = assigned_items.where(purchase_order_id: purchase_order_id) if is_purchase

    existing_count = assigned_items.count
    desired_count = quantity.to_i
    difference = desired_count - existing_count

    # Actualiza inventario existente
    assigned_items.each do |item|
      item.update!(
        purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : item.purchase_cost,
        sold_price: respond_to?(:unit_final_price) ? unit_final_price.to_f : item.sold_price,
        status: inventory_status_from_order,
        status_changed_at: Time.current
      )
    end

    if difference > 0
      # Crear inventario adicional
      difference.times do
        Inventory.create!(
          product: product,
          status: inventory_status_from_order,
          status_changed_at: Time.current,
          purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : nil,
          sold_price: respond_to?(:unit_final_price) ? unit_final_price.to_f : nil,
          purchase_order_id: is_purchase ? purchase_order_id : nil,
          sale_order_id: is_sale ? sale_order_id : nil,
          purchase_order_item_id: is_purchase ? id : nil
        )
      end
      append_pending_note(difference) if is_sale
    elsif difference < 0
      # Eliminar exceso de inventario no vendido/reservado
      assigned_items
        .where(status: [ :in_transit, :available ])
        .order(status_changed_at: :desc)
        .limit(difference.abs)
        .destroy_all
      remove_pending_note if is_sale
    else
      remove_pending_note if is_sale
    end
  end


  def reserve_inventory_items(items)
    items.each do |item|
      item.update!(
        status: :reserved,
        sale_order_id: respond_to?(:sale_order_id) ? sale_order_id : nil,
        purchase_order_id: respond_to?(:purchase_order_id) ? purchase_order_id : nil,
        status_changed_at: Time.current
      )
    end
  end

  def release_inventory_items(items)
    items.each do |item|
      item.update!(
        status: :available,
        sale_order_id: nil,
        purchase_order_id: nil,
        status_changed_at: Time.current
      )
    end
  end

  def append_pending_note(remaining)
    return unless respond_to?(:sale_order) && sale_order.persisted?

    line_note = "🛑 Producto #{product.product_name} (#{product.product_sku}): cliente pidió #{quantity}, solo reservados #{quantity - remaining}"
    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    lines << line_note
    sale_order.update!(notes: lines.join("\n"))
  end

  def remove_pending_note
    return unless respond_to?(:sale_order) && sale_order.persisted? && sale_order.notes.present?

    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    sale_order.update!(notes: lines.join("\n"))
  end

  # Determina el estado de inventario basado en el estado de la orden
  def inventory_status_from_order
    case parent_order&.status
    when "Pending", "In Transit"
      :in_transit
    when "Delivered"
      :available
    when "Canceled"
      :scrap
    when "Shipped", "Confirmed"
      :sold
    else
      :in_transit
    end
  end

  # Devuelve el objeto padre (sale_order o purchase_order)
  def parent_order
    respond_to?(:sale_order) ? sale_order : (respond_to?(:purchase_order) ? purchase_order : nil)
  end
end
