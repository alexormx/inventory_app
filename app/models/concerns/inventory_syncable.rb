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

    # No cambiar el estado de los items existentes (para no sobreescribir reservados/vendidos)
    # Solo asegurar vínculos básicos si hiciera falta, sin tocar status.
    existing_items.find_each do |item|
      updates = {}
      updates[:purchase_order_id] = purchase_order_id if item.purchase_order_id != purchase_order_id
      updates[:product_id] = product_id if item.product_id != product_id
      # Mantener purchase_cost intacto a menos que esté en blanco
      if item.purchase_cost.nil? && respond_to?(:unit_compose_cost_in_mxn)
        updates[:purchase_cost] = unit_compose_cost_in_mxn.to_f
      end
      item.update!(updates) if updates.any?
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
    # Estado actual asignado a la SO por producto
    assigned = Inventory.where(product_id: product.id, sale_order_id: sale_order_id)
    current_count = assigned.count
    needed = desired_quantity - current_count

    if needed > 0
      to_assign = needed

      # 1) available -> reserved
      avl_items = Inventory.where(product_id: product.id, status: :available, sale_order_id: nil)
                           .order(:status_changed_at)
                           .limit(to_assign)
      reserve_inventory_items(avl_items)
      to_assign -= avl_items.count

      # 2) in_transit -> pre_* según estado de SO
      if to_assign > 0
        it_items = Inventory.where(product_id: product.id, status: :in_transit, sale_order_id: nil)
                            .order(:status_changed_at)
                            .limit(to_assign)
        it_items.each do |item|
          target_status = (sale_order.status == "Confirmed") ? :pre_sold : :pre_reserved
          item.update!(
            status: target_status,
            sale_order_id: sale_order_id,
            sale_order_item_id: id,
            status_changed_at: Time.current,
            sold_price: respond_to?(:unit_final_price) ? unit_final_price.to_f : item.sold_price
          )
        end
        to_assign -= it_items.count
      end

      # 3) Faltantes -> crear preventa y reflejar en la línea
      if to_assign > 0
        PreorderReservation.create!(
          product: product,
          user: sale_order.user,
          sale_order: sale_order,
          quantity: to_assign,
          status: :pending,
          reserved_at: Time.current
        )
        # Actualiza contador en la línea (si existe el atributo)
        if self.respond_to?(:preorder_quantity)
          update_column(:preorder_quantity, preorder_quantity.to_i + to_assign)
        end
      end
    elsif needed < 0
      # Exceso de asignación: liberar reservados (no toca vendidos ni pre_*)
      extra_items = assigned.where(status: :reserved)
                            .order(status_changed_at: :desc)
                            .limit(needed.abs)
      release_inventory_items(extra_items)
      # No agregar notas
    end
  end

  def reserve_inventory_items(items)
    items.each do |item|
      item.update!(
        status: :reserved,
        sale_order_id: sale_order_id,
  sale_order_item_id: id,
        status_changed_at: Time.current,
        sold_price: respond_to?(:unit_final_price) ? unit_final_price.to_f : item.sold_price
      )
    end
  end

  # Notas desactivadas: ya no se agrega/remueve texto en SaleOrder.notes

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
  sale_order_item_id: nil,
        status_changed_at: Time.current
      )
    end
  end
end
