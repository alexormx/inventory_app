class SaleOrder < ApplicationRecord
  include CustomIdGenerator
  belongs_to :user

  has_many :inventory, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error
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

  before_validation :set_default_status, on: :create
  before_create :generate_custom_id

  def total_paid
    payments.where(status: "Completed").sum(:amount)
  end

  def fully_paid?
    total_paid >= total_order_value
  end

  def update_status_if_fully_paid!
    if fully_paid? && status != "Confirmed"
      update!(status: "Confirmed")
    elsif !fully_paid? && status == "Confirmed"
      update!(status: "Pending")
    end
  end

  private

  def ensure_payment_and_shipment_present
    case status
    when "Confirmed"
      errors.add(:payment, "must exist to confirm the order") unless payments.any?
    when "Shipped"
      errors.add(:payment, "must exist to ship the order") unless payments.any?
      errors.add(:shipment, "must exist to ship the order") unless shipment.present?
    when "Delivered"
      errors.add(:payment, "must exist to deliver the order") unless payment.any?
      errors.add(:shipment, "must exist to deliver the order") unless shipment.present?

    end
  end

  def generate_custom_id
    self.id = generate_unique_id("SO") if id.blank?
  end

  def set_default_status
    self.status ||= "Pending"
  end
end

