# app/models/concerns/inventory_syncable.rb
module InventorySyncable
  extend ActiveSupport::Concern

  def sync_inventory_records
    Rails.logger.debug "[🔍 InventorySync] Syncing for product_id=#{product_id}, order_id=#{parent_order&.id}"
    return unless product && parent_order&.persisted?

    is_sale = respond_to?(:sale_order)
    is_purchase = respond_to?(:purchase_order)

    desired_quantity = quantity.to_i

    if is_purchase
      sync_inventory_for_purchase(desired_quantity)
    elsif is_sale
      sync_inventory_for_sale(desired_quantity)
    end
  rescue => e
    Rails.logger.error "[❌ InventorySync Error] #{e.class}: #{e.message}"
    raise
  end

  private

  def sync_inventory_for_purchase(desired_quantity)
    # Sincronizar por línea específica para evitar colisiones entre líneas con el mismo SKU
    existing_items = Inventory.where(purchase_order_item_id: id)
    current_count = existing_items.count
    difference = desired_quantity - current_count

    # Update existing items
    existing_items.each do |item|
      item.update!(
        status: inventory_status_from_order,
        status_changed_at: Time.current,
        purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : item.purchase_cost,
        purchase_order_id: purchase_order_id,
        product_id: product_id
      )
    end

    if difference > 0
      difference.times do
        Inventory.create!(
          product: product,
          purchase_order_id: purchase_order_id,
          purchase_order_item_id: id,
          status: inventory_status_from_order,
          status_changed_at: Time.current,
          purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : 0
        )
      end
    elsif difference < 0
      # Remove excess unassigned items
      existing_items.where(status: [ :in_transit, :available ])
                    .order(status_changed_at: :desc)
                    .limit(difference.abs)
                    .destroy_all
    end
  end

  def sync_inventory_for_sale(desired_quantity)
    # Only assign inventory if it's not already assigned
    assigned = Inventory.where(product_id: product.id, sale_order_id: sale_order_id)
    current_count = assigned.count
    needed = desired_quantity - current_count

    if needed > 0
      available_items = Inventory.assignable
                                 .where(product_id: product.id)
                                 .limit(needed)

      reserve_inventory_items(available_items)

      if available_items.count < needed
        append_pending_note(needed - available_items.count)
      else
        remove_pending_note
      end
    elsif needed < 0
      # Too many assigned, release extras
      extra_items = assigned.where(status: :reserved)
                            .order(status_changed_at: :desc)
                            .limit(needed.abs)
      release_inventory_items(extra_items)
      remove_pending_note
    end
  end

  def reserve_inventory_items(items)
    items.each do |item|
      item.update!(
        status: :reserved,
        sale_order_id: sale_order_id,
        status_changed_at: Time.current,
        sold_price: respond_to?(:unit_final_price) ? unit_final_price.to_f : item.sold_price
      )
    end
  end

  def append_pending_note(remaining)
    return unless respond_to?(:sale_order) && sale_order.persisted?

    line_identifier = id || object_id # usa ID si existe, o fallback a object_id temporal si aún no está persistido
    note_prefix = "🛑 Producto #{product.product_name} (#{product.product_sku}), línea #{line_identifier}:"

    new_line = "#{note_prefix} cliente pidió #{quantity}, solo reservados #{quantity - remaining}"

    # Elimina notas anteriores de esta misma línea (basado en ID)
    existing_lines = sale_order.notes.to_s.split("\n")
    filtered_lines = existing_lines.reject { |line| line.starts_with?(note_prefix) }

    # Agrega la nueva nota
    filtered_lines << new_line
    sale_order.update!(notes: filtered_lines.join("\n"))
  end

  def remove_pending_note
    return unless respond_to?(:sale_order) && sale_order.persisted?

    line_identifier = id || object_id
    note_prefix = "🛑 Producto #{product.product_name} (#{product.product_sku}), línea #{line_identifier}:"

    updated_notes = sale_order.notes.to_s.split("\n").reject { |line| line.starts_with?(note_prefix) }
    sale_order.update!(notes: updated_notes.join("\n"))
  end

  def inventory_status_from_order
    case parent_order&.status
    when "Pending", "In Transit" then :in_transit
    when "Delivered" then :available
    when "Canceled" then :scrap
    when "Shipped", "Confirmed" then :sold
    else :in_transit
    end
  end

  def parent_order
    respond_to?(:sale_order) ? sale_order : (respond_to?(:purchase_order) ? purchase_order : nil)
  end

  def release_inventory_items(items)
    items.each do |item|
      item.update!(
        status: :available,
        sale_order_id: nil,
        status_changed_at: Time.current
      )
    end
  end
end
