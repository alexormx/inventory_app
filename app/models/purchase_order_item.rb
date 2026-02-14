# frozen_string_literal: true

class PurchaseOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :purchase_order, inverse_of: :purchase_order_items
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }

  before_validation :compute_line_volume_and_weight, if: :should_compute_volume_weight?
  before_update :ensure_free_units_for_quantity_reduction, if: :will_reduce_quantity?
  before_destroy :ensure_enough_free_inventory_to_remove
  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  after_commit :update_product_stats
  after_commit :recalculate_parent_order_totals

  private

  def will_reduce_quantity?
    quantity_changed? && quantity_change_to_be_saved.first.to_i > quantity_change_to_be_saved.last.to_i
  end

  def ensure_free_units_for_quantity_reduction
    old_qty, new_qty = quantity_change_to_be_saved
    desired_removal = old_qty.to_i - new_qty.to_i
    return unless free_inventory_scope.count < desired_removal

    errors.add(:base, "Not enough free inventory to reduce quantity by #{desired_removal}.")
    throw :abort
    
  end

  def ensure_enough_free_inventory_to_remove
    desired_removal_qty = quantity.to_i
    return unless free_inventory_scope.count < desired_removal_qty

    errors.add(:base, 'Cannot remove line: not enough free inventory to remove.')
    throw :abort
    
  end

  def free_inventory_scope
    Inventory.where(
      product_id: product_id,
      purchase_order_id: purchase_order_id,
      sale_order_id: nil,
      status: %w[available in_transit]
    )
  end

  def should_compute_volume_weight?
    product.present? && quantity.present? && (
      total_line_volume.blank? || total_line_weight.blank? || will_save_change_to_quantity?
    )
  end

  def compute_line_volume_and_weight
    unit_volume = product.unit_volume_cm3.to_f
    self.total_line_volume = quantity.to_i * unit_volume
    self.total_line_weight = quantity.to_i * product.weight_gr.to_f
  end

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  rescue StandardError => e
    Rails.logger.error "[POI#update_product_stats] #{e.class}: #{e.message}"
  end

  def recalculate_parent_order_totals
    return if purchase_order_id.blank?

    po = PurchaseOrder.find_by(id: purchase_order_id)
    return unless po

    # Si hay cambios en items y la PO tenía costos distribuidos, limpiar el timestamp
    # porque los costos distribuidos en las líneas ya no son válidos
    po.update_column(:costs_distributed_at, nil) if po.costs_distributed_at.present?

    po.recalculate_totals!(persist: true)
  rescue StandardError => e
    Rails.logger.error "[POI#recalculate_parent_order_totals] #{e.class}: #{e.message}"
  end
end
