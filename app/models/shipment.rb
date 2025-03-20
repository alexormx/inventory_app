class Shipment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id"

  validates :tracking_number, presence: true, uniqueness: true
  validates :carrier, presence: true
  validates :status, presence: true, inclusion: { in: %w[Pending Shipped Delivered] }
  validates :estimated_delivery, presence: true
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }

  # Use the custom DateValidator
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }

  before_update :update_last_status_change

  private

  def update_last_status_change
    if status_changed?
      self.last_update = Time.current
    end
  end
end
