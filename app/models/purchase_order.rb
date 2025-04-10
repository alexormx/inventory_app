class PurchaseOrder < ApplicationRecord
  include CustomIdGenerator

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
  after_update :update_inventory_status_based_on_order_status



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
    self.id = generate_unique_id("PO") if id.blank?
  end

  def update_inventory_status_based_on_order_status
    return unless saved_change_to_status?

    new_status = case status
                 when "Delivered" then :available
                 when "Canceled" then :scrap
                 when "Pending", "In Transit" then :in_transit
                 else nil
                 end

    return unless new_status

    inventory.where.not(status: [:sold, :reserved])
             .update_all(status: Inventory.statuses[new_status], status_changed_at: Time.current)
  end

end
