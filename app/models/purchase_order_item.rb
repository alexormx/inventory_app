class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :product
  
  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  has_many :inventory

  after_destroy :update_product_stock

  private

  def update_product_stock
    inventory.update_all(status: "Removed", status_changed_at: Time.current)
    product.update_stock_quantity!
  end
end