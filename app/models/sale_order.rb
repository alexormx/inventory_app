class SaleOrder < ApplicationRecord
  belongs_to :user
  has_many :inventory, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_one :payment, dependent: :restrict_with_error
  has_one :shipment, foreign_key: "sale_order_id", dependent: :restrict_with_error

  validates :order_date, presence: true
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :total_tax, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_order_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[Pending Confirmed Shipped Delivered Canceled] }
  validate :ensure_payment_and_shipment_present

  after_commit :update_product_sales_stats, on: [:create, :update]

  private

  def ensure_payment_and_shipment_present
    if status == "Confirmed" && !payment
      errors.add(:payment, "must be present when order is confirmed")
    end

    if status == "Shipped" && !shipment
      errors.add(:shipment, "must be present when order is shipped")
    end
  end

  def update_product_sales_stats
    sale_order_items.each do |item|
      Products::UpdateSalesStatsService.new(item.product).call
    end
  end
end
