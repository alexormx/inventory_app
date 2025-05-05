class Shipment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"

  validates :tracking_number, presence: true
  validates :carrier, presence: true
  validates :estimated_delivery, presence: true
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }

  # Use the custom DateValidator
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }

  before_update :update_last_status_change

  enum :status, [ :pending, :shipped, :delivered, :canceled, :returned ], default: :pending

  private

  def update_last_status_change
    if status_changed?
      self.last_update = Time.current
    end
  end
end
