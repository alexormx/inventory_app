# frozen_string_literal: true

# app/models/concerns/inventory_syncable.rb
module InventorySyncable
  extend ActiveSupport::Concern

  # Una pieza que ya tiene dueño no vuelve a ser suministro libre porque la
  # línea de compra cambie de cantidad. El estado derivado de la PO describe
  # únicamente stock sin comprometer.
  COMMITTED_INVENTORY_STATUSES = %w[reserved pre_reserved pre_sold sold].freeze

  # Piezas retiradas: ya no representan cantidad viva de la línea, así que no
  # se cuentan ni se reescriben.
  RETIRED_INVENTORY_STATUSES = %w[scrap].freeze

  def sync_inventory_records
    Rails.logger.debug { "[🔍 InventorySync] Syncing for product_id=#{product_id}, order_id=#{parent_order&.id}" }
    return unless product && parent_order&.persisted?

    is_sale = respond_to?(:sale_order)
    is_purchase = respond_to?(:purchase_order)

    desired_quantity = quantity.to_i

    if is_purchase
      sync_inventory_for_purchase(desired_quantity)
    elsif is_sale
      sync_inventory_for_sale(desired_quantity)
    end
  rescue StandardError => e
    Rails.logger.error "[❌ InventorySync Error] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    raise
  end

  private

  def sync_inventory_for_purchase(desired_quantity)
    locked_product = Product.lock.find(product.id)
    # Manage inventory per line item to avoid interfering across lines for the same PO
    existing_items = Inventory.where(product_id: locked_product.id, purchase_order_item_id: id)
    live_items = existing_items.where.not(status: RETIRED_INVENTORY_STATUSES)
    current_count = live_items.count
    difference = desired_quantity - current_count

    # Update existing items
    live_items.each do |item|
      item.defer_preorder_reconciliation = true
      attributes = {
        purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : item.purchase_cost,
        purchase_order_item_id: id
      }
      # Sólo el stock libre sigue al estado de la PO. Reescribir una pieza
      # comprometida la devolvería a in_transit, y como in_transit cuenta como
      # "libre" se le borraría el vínculo con la orden del cliente.
      unless committed_inventory?(item)
        attributes[:status] = inventory_status_from_order
        attributes[:status_changed_at] = Time.current
      end
      item.update!(attributes)
    end

    if difference.positive?
      difference.times do
        inventory = Inventory.new(
          product: locked_product,
          purchase_order_id: purchase_order_id,
          purchase_order_item_id: id,
          status: inventory_status_from_order,
          status_changed_at: Time.current,
          purchase_cost: respond_to?(:unit_compose_cost_in_mxn) ? unit_compose_cost_in_mxn.to_f : 0
        )
        inventory.defer_preorder_reconciliation = true
        inventory.save!
      end
    elsif difference.negative?
      retire_excess_inventory(live_items, difference.abs)
    end

    Preorders::PreorderAllocator.new(locked_product).call
  end

  def committed_inventory?(item)
    item.sale_order_id.present? || COMMITTED_INVENTORY_STATUSES.include?(item.status.to_s)
  end

  # Reducir la cantidad de una PO retira suministro entrante que ya no va a
  # llegar. La pieza NO se destruye: InventoryEvent es un libro de auditoría con
  # llave foránea a inventories, así que borrar la fila rompe el rastro (o
  # exige borrar la auditoría con ella). La aplicación ya tiene este ciclo de
  # vida —cancelar una PO completa retira sus piezas no comprometidas a
  # :scrap— y una reducción de cantidad es una cancelación parcial de la misma
  # orden, así que sigue exactamente el mismo camino.
  #
  # Sólo se retiran piezas genuinamente libres; las comprometidas quedan fuera
  # del alcance y la guarda de PurchaseOrderItem ya impide pedir más de las que
  # hay libres.
  def retire_excess_inventory(live_items, count)
    retirable = live_items.where(status: %i[in_transit available], sale_order_id: nil)
                          .order(status_changed_at: :desc, id: :desc)
                          .lock
                          .limit(count)
                          .to_a

    retirable.each do |item|
      previous_status = item.status
      item.defer_preorder_reconciliation = true
      item.update!(status: :scrap, status_changed_at: Time.current)
      log_retirement_event(item, previous_status)
    end
  end

  def log_retirement_event(item, previous_status)
    InventoryEvent.create!(
      inventory: item,
      product_id: item.product_id,
      event_type: 'status_change',
      metadata: {
        'reason' => 'purchase_order_quantity_reduced',
        'previous_status' => previous_status,
        'new_status' => item.status,
        'purchase_order_id' => item.purchase_order_id,
        'purchase_order_item_id' => item.purchase_order_item_id
      }
    )
  end

  def sync_inventory_for_sale(_desired_quantity)
    result = InventoryServices::ReserveSaleOrderItem.call(self, strict: false)

    if result.missing.positive?
      append_pending_note(result.missing)
    else
      remove_pending_note
    end
    sync_location_warning(result.inventories)
  end

  def append_pending_note(remaining)
    return unless respond_to?(:sale_order) && sale_order.persisted?

    sale_order.upsert_pending_note(self, remaining)
  end

  def remove_pending_note
    return unless respond_to?(:sale_order) && sale_order.persisted?

    sale_order.remove_pending_note_for(self)
  end

  # Alerta si alguna pieza asignada no tiene ubicación física (difícil de localizar).
  def sync_location_warning(items)
    return unless respond_to?(:sale_order) && sale_order.persisted?

    without_location = items.count { |item| !item.located? }
    if without_location.positive?
      sale_order.upsert_location_warning_note(self, without_location)
    else
      sale_order.remove_location_warning_note_for(self)
    end
  end

  def inventory_status_from_order
    case parent_order&.status
    when 'Delivered' then :available
    when 'Canceled' then :scrap
    when 'Shipped', 'Confirmed' then :sold
    else :in_transit
    end
  end

  def parent_order
    if respond_to?(:sale_order)
      sale_order
    else
      (respond_to?(:purchase_order) ? purchase_order : nil)
    end
  end

  def release_inventory_items(items)
    items.each do |item|
      attrs = {
        status: :available,
        sale_order_id: nil,
        sold_price: nil,
        status_changed_at: Time.current
      }
      attrs[:sale_order_item_id] = nil if Inventory.column_names.include?('sale_order_item_id')

      item.update!(attrs)
    end
  end
end
