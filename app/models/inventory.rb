class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true, foreign_key: "purchase_order_id", primary_key: "id"
  belongs_to :sale_order, optional: true, foreign_key: "sale_order_id", primary_key: "id"
  belongs_to :product, foreign_key: "product_id"

  validates :purchase_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: %w[Available Reserved Sold InTransit Lost Damaged Scrap] }

  before_update :track_status_change

  private

  def track_status_change
    if status_changed?
      self.last_status_change = Time.current
    end
  end
end
