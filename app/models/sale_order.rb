class SaleOrder < ApplicationRecord
  include CustomIdGenerator
  belongs_to :user
  before_create :generate_custom_id

  has_many :inventory, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_one :payment, dependent: :restrict_with_error
  has_one :shipment, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_many :sale_order_items, dependent: :destroy
  has_many :products, through: :sale_order_items

  accepts_nested_attributes_for :sale_order_items, allow_destroy: true

  validates :order_date, presence: true
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :total_tax, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_order_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[Pending Confirmed Shipped Delivered Canceled] }
  validate :ensure_payment_and_shipment_present

  private

  def ensure_payment_and_shipment_present
    if status == "Confirmed" && !payment
      errors.add(:payment, "must be present when order is confirmed")
    end

    if status == "Shipped" && !shipment
      errors.add(:shipment, "must be present when order is shipped")
    end
  end

  def generate_custom_id
    self.id = generate_unique_id("SO") if id.blank?
  end
end

