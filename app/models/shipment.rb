class Shipment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"

  validates :tracking_number, presence: true
  validates :carrier, presence: true
  validates :estimated_delivery, presence: true
  validates :shipping_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Use the custom DateValidator
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }
  validate :actual_not_before_estimated

  before_update :update_last_status_change
  after_save :update_sale_order_totals_if_shipping_changed

  enum :status, [ :pending, :shipped, :delivered, :canceled, :returned ], default: :pending

  private

  def update_last_status_change
    if status_changed?
      self.last_update = Time.current
    end
  end

  def actual_not_before_estimated
    return if actual_delivery.blank? || estimated_delivery.blank?
    if actual_delivery < estimated_delivery
      errors.add(:actual_delivery, "no puede ser anterior a la fecha estimada")
    end
  end

  def update_sale_order_totals_if_shipping_changed
    if saved_change_to_shipping_cost?
      sale_order.update!(shipping_cost: shipping_cost)
      sale_order.recalculate_totals!
    end
  end
end
