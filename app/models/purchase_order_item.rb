class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :product
  has_many :inventory
  
  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  after_destroy :update_product_stock
  after_save :sync_inventory_records
  before_destroy :delete_related_inventory
  after_save :update_product_purchase_stats
  after_destroy :update_product_purchase_stats

  private

  def update_product_stock
    inventory.update_all(status: "Removed", status_changed_at: Time.current)
  end

  def sync_inventory_records
    existing_items = Inventory.where(purchase_order_item_id: id)
    current_count = existing_items.count
    difference = quantity - current_count
  
    if difference > 0
      # Add new inventory items
      difference.times do
        inventory.create!(
          product: product,
          purchase_order: purchase_order,
          purchase_cost: unit_compose_cost_in_mxn.to_f,
          status: inventory_status_from_po,
          status_changed_at: Time.current,
          purchase_order_item_id: id
        )
      end
    elsif difference < 0
      # Remove extra inventory items (only if not sold or reserved)
      items_to_delete = existing_items.where(status: [:in_transit, :available]).limit(difference.abs)
      items_to_delete.destroy_all
    end
  end

  def update_product_purchase_stats
    Products::UpdatePurchaseStatsService.new(product).call
  end

  def inventory_status_from_po
    case purchase_order.status
    when "Pending", "In Transit"
      :in_transit
    when "Delivered"
      :available
    when "Canceled"
      :scrap # or use :returned or :canceled if you prefer
    else
      :in_transit # fallback default
    end
  end

  def delete_related_inventory
    Inventory.where(purchase_order_id: purchase_order_id, product_id: product_id)
             .where.not(status: [:sold, :reserved])
             .destroy_all
  end
  
end