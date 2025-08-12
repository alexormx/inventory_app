class PurchaseOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :purchase_order, inverse_of: :purchase_order_items
  belongs_to :product

  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  after_save :sync_inventory_records
  after_commit :update_product_stats

  before_update :ensure_free_units_for_quantity_reduction, if: :will_reduce_quantity?
  before_destroy :ensure_enough_free_inventory_to_remove

  private

  def will_reduce_quantity?
    quantity_changed? && quantity_change_to_be_saved.first.to_i > quantity_change_to_be_saved.last.to_i
  end

  def ensure_free_units_for_quantity_reduction
    old_qty, new_qty = quantity_change_to_be_saved
    desired_removal = old_qty.to_i - new_qty.to_i
    if free_inventory_scope.count < desired_removal
      errors.add(:base, "Not enough free inventory to reduce quantity by #{desired_removal}.")
      throw :abort
    end
  end

  def ensure_enough_free_inventory_to_remove
    desired_removal_qty = quantity.to_i
    if free_inventory_scope.count < desired_removal_qty
      errors.add(:base, "Cannot remove line: not enough free inventory to remove.")
      throw :abort
    end
  end

  def free_inventory_scope
    Inventory.where(
      product_id: product_id,
      purchase_order_id: purchase_order_id,
      sale_order_id: nil,
      status: %w[available in_transit]
    )
  end

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  rescue => e
    Rails.logger.error "[POI#update_product_stats] #{e.class}: #{e.message}"
  end

end
