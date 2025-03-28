class PurchaseOrder < ApplicationRecord
  belongs_to :user
  before_create :generate_custom_id

  has_many :inventory, foreign_key: "purchase_order_id", dependent: :restrict_with_error
  has_many :purchase_order_items, dependent: :destroy
  has_many :products, through: :purchase_order_items

  accepts_nested_attributes_for :purchase_order_items, allow_destroy: true

  validates :order_date, presence: true
  validates :expected_delivery_date, presence: true
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_order_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :shipping_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :other_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: ["Pending", "In Transit", "Delivered", "Canceled"]  }

  validate :expected_delivery_after_order_date
  validate :actual_delivery_after_expected_delivery

  private

  def expected_delivery_after_order_date
    if expected_delivery_date.present? && order_date.present? && expected_delivery_date < order_date
      errors.add(:expected_delivery_date, "must be after the order date")
    end
  end

  def actual_delivery_after_expected_delivery
    return if actual_delivery_date.nil? || expected_delivery_date.nil?

    if actual_delivery_date < expected_delivery_date
      errors.add(:actual_delivery_date, "must be after or equal to expected delivery date")
    end
  end

  def generate_custom_id
    return if self.id.present?
    return unless self.order_date.present?  # Ensure order_date is set
  
    year = order_date.year
  
    last_order = PurchaseOrder
      .where("id LIKE ?", "PO-#{year}-%")
      .order(:created_at)
      .last
  
    sequence = if last_order
                 last_order.id.split("-").last.to_i + 1
               else
                 1
               end
  
    self.id = format("PO-%<year>d-%<seq>05d", year: year, seq: sequence)
  end
end
