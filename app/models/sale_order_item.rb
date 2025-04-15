class SaleOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :sale_order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_line_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  before_destroy :unset_inventory_links
  after_destroy :release_inventory_and_update_notes
  after_commit :update_product_stats


  private

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

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  end

  # FUTURO: Soporte para backorders
end
