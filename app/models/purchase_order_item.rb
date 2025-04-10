class PurchaseOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :purchase_order
  belongs_to :product
  has_many :inventories

  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  after_destroy :update_product_stock
  after_save :sync_inventory_records
  before_destroy :delete_related_inventory
  after_save :update_product_stats
  after_destroy :update_product_purchase_stats

  private

  def update_product_stock
    inventories.update_all(status: "Removed", status_changed_at: Time.current)
  end

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  end

  def delete_related_inventory
    Inventory.where(purchase_order_id: purchase_order_id, product_id: product_id)
             .where.not(status: [:sold, :reserved])
             .destroy_all
  end
end
