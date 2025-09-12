class CanceledOrderItem < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"
  belongs_to :purchase_order
  belongs_to :product

  validates :canceled_quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :sale_price_at_cancellation, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :cancellation_reason, presence: true

  # Optional: Track cancellation time automatically if not provided
  before_create :set_canceled_at

  private

  def set_canceled_at
    self.canceled_at ||= Time.current
  end
end
