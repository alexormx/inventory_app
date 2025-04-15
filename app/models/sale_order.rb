class SaleOrder < ApplicationRecord
  include CustomIdGenerator
  belongs_to :user
  before_create :generate_custom_id

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

  after_commit :auto_update_status

  def total_paid
    payments.where(status: "Completed").sum(:amount)
  end

  def fully_paid?
    total_paid >= total_order_value
  end

  def update_status_if_fully_paid!
    update!(status: "Confirmed") if fully_paid? && status != "Confirmed"
  end

  private

  def ensure_payment_and_shipment_present
    case status
    when "Confirmed"
      errors.add(:payment, "must exist to confirm the order") unless payment
    when "Shipped"
      errors.add(:payment, "must exist to ship the order") unless payment
      errors.add(:shipment, "must exist to ship the order") unless shipment
    when "Delivered"
      errors.add(:payment, "must exist to deliver the order") unless payment
      errors.add(:shipment, "must exist to deliver the order") unless shipment
    end
  end

  def auto_update_status
    return if status == "Delivered" # Delivered must remain final unless explicitly changed

    if shipment&.delivered? && payment.present?
      update_column(:status, "Delivered")
    elsif shipment.present? && payment.present?
      update_column(:status, "Shipped")
    elsif payment.present?
      update_column(:status, "Confirmed")
    end
  end

  def generate_custom_id
    self.id = generate_unique_id("SO") if id.blank?
  end
end

