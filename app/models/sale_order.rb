class SaleOrder < ApplicationRecord
  belongs_to :user
  before_create :generate_custom_id

  has_many :inventory, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_one :payment, dependent: :restrict_with_error
  has_one :shipment, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_many :sale_order_items, dependent: :destroy
  has_many :products, through: :sale_order_items

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

  def generate_custom_id
    return if self.id.present?
    return unless self.order_date.present?  # Ensure order_date is set
  
    year = order_date.year
    month = order_date.month

  
    last_order = SaleOrder
      .where("id LIKE ?", "SO-#{year}-#{month}-%")
      .order(:created_at)
      .last
  
    sequence = if last_order
                 last_order.id.split("-").last.to_i + 1
               else
                 1
               end
  
    self.id = format("SO-%<year>d-%<month>02d-%<seq>03d", year: year, month: month, seq: sequence)
  end
end

