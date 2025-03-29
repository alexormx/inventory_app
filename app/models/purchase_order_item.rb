class PurchaseOrderItem < ApplicationRecord
  belongs_to :purchase_order
  belongs_to :product
  
  validates :product_id, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

end