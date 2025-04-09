class SaleOrderItem < ApplicationRecord
  belongs_to :sale_order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_line_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  before_destroy :unset_inventory_links
  after_destroy :release_inventory_and_update_notes
  after_save :update_product_stats

  private

  def sync_inventory_records
    return unless product && sale_order.persisted?

    assigned_items = Inventory.where(sale_order_id: sale_order.id, product_id: product.id)
    needed_quantity = quantity - assigned_items.count

    if needed_quantity > 0
      available_items = Inventory.assignable
                                 .where(product_id: product_id)
                                 .order(:status_changed_at)
                                 .limit(needed_quantity)

      available_items.each do |item|
        item.update!(
          status: :reserved,
          sale_order_id: sale_order_id,
          status_changed_at: Time.current
        )
      end

      append_pending_note(needed_quantity - available_items.size) if available_items.size < needed_quantity
    elsif needed_quantity < 0
      assigned_items.order(status_changed_at: :desc)
                    .limit(needed_quantity.abs)
                    .each do |item|
        item.update!(
          status: :available,
          sale_order_id: nil,
          status_changed_at: Time.current
        )
      end
      remove_pending_note
    else
      remove_pending_note
    end
  end

  def release_inventory_and_update_notes
    Inventory.where(sale_order_id: sale_order.id, product_id: product_id).each do |item|
      if item.status.in?(%w[reserved sold])
        item.update!(
          status: :available,
          sale_order_id: nil,
          status_changed_at: Time.current
        )
      end
    end
    remove_pending_note
  end

  def unset_inventory_links
    Inventory.where(sale_order_id: sale_order_id).update_all(sale_order_id: nil)
  end

  def append_pending_note(remaining)
    return unless sale_order.persisted?

    line_note = "🛑 Producto #{product.product_name} (#{product.product_sku}): cliente pidió #{quantity}, solo reservados #{quantity - remaining}"
    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    lines << line_note
    sale_order.update!(notes: lines.join("\n"))
  end

  def remove_pending_note
    return unless sale_order.persisted? && sale_order.notes.present?

    lines = sale_order.notes.to_s.split("\n").reject { |line| line.include?(product.product_sku) }
    sale_order.update!(notes: lines.join("\n"))
  end

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  end

  # FUTURO: Soporte para backorders
end
