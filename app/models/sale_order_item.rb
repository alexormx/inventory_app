class SaleOrderItem < ApplicationRecord
  belongs_to :sale_order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_line_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # 🔧 Callbacks
  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  before_destroy :unset_inventory_links
  after_destroy :release_inventory_and_update_notes

  private

  # 🔁 Sincroniza inventario con la cantidad solicitada
  def sync_inventory_records
    return unless product && sale_order.persisted?

    assigned_items = Inventory.where(sale_order_id: sale_order_id, sale_order_item_id: id)
    needed_quantity = quantity - assigned_items.count

    if needed_quantity > 0
      available_items = Inventory.assignable.where(product_id: product_id)
                                           .order(:status_changed_at)
                                           .limit(needed_quantity)

      available_items.each do |item|
        item.update!(
          status: :reserved,
          sale_order_id: sale_order_id,
          sale_order_item_id: id,
          status_changed_at: Time.current
        )
      end

      append_pending_note(needed_quantity - available_items.size) if available_items.size < needed_quantity
    elsif needed_quantity < 0
      # Libera inventario excedente
      assigned_items.order(status_changed_at: :desc)
                    .limit(needed_quantity.abs)
                    .each do |item|
        item.update!(
          status: :available,
          sale_order_id: nil,
          sale_order_item_id: nil,
          status_changed_at: Time.current
        )
      end
      remove_pending_note
    else
      remove_pending_note
    end
  end

  # 🔒 Libera inventario reservado o vendido
  def release_inventory_and_update_notes
    Inventory.where(sale_order_id: sale_order.id, sale_order_item_id: id).each do |item|
      if item.status.in?(%w[reserved sold])
        item.update!(
          status: :available,
          sale_order_id: nil,
          sale_order_item_id: nil,
          status_changed_at: Time.current
        )
      end
    end
    remove_pending_note
  end

  # 🧼 Limpia relaciones antes de eliminar
  def unset_inventory_links
    Inventory.where(sale_order_item_id: id).update_all(sale_order_id: nil, sale_order_item_id: nil)
  end

  # 📝 Agrega/actualiza nota de pendiente por producto
  def append_pending_note(remaining)
    return unless sale_order.persisted?

    line_note = "🛑 Producto #{product.product_name} (#{product.product_sku}): cliente pidió #{quantity}, solo reservados #{quantity - remaining}"
    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    lines << line_note
    sale_order.update!(notes: lines.join("\n"))
  end

  # ✅ Elimina la nota asociada a este item si ya no hay pendiente
  def remove_pending_note
    return unless sale_order.persisted? && sale_order.notes.present?

    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    sale_order.update!(notes: lines.join("\n"))
  end

  # 🛠 Utilidad interna para pruebas o limpieza si se requiere
  def delete_related_inventory
    Inventory.where(sale_order_item_id: id).each do |item|
      item.update!(
        status: :available,
        sale_order_id: nil,
        sale_order_item_id: nil,
        status_changed_at: Time.current
      )
    end
  end

  # 📌 FUTURO: Soporte para backorders/pre-órdenes
end
