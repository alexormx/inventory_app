class Product < ApplicationRecord
  belongs_to :preferred_supplier, class_name: "User", optional: true
  belongs_to :last_supplier, class_name: "User", optional: true


  has_many :inventory, dependent: :restrict_with_error
  has_many :canceled_order_items, dependent: :restrict_with_error
  has_many :purchase_order_items
  has_many :purchase_orders, through: :purchase_order_items
  has_many_attached :product_images

  validates :product_sku, presence: true, uniqueness: true
  validates :product_name, presence: true
  validates :selling_price, presence: true, numericality: { greater_than: 0 }
  validates :maximum_discount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_limited_stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :minimum_price_not_exceed_selling_price

  private

  def minimum_price_not_exceed_selling_price
    if minimum_price.present? && selling_price.present? && minimum_price > selling_price
      errors.add(:minimum_price, "cannot be higher than the selling price")
    end
  end


end
