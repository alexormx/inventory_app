class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :product

  enum :status, [
    :available,
    :reserved,
    :in_transit,
    :sold,
    :damaged,
    :lost,
    :returned,
    :scrap],
    default: :available


  validates :purchase_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: Inventory.statuses.keys }


  before_update :track_status_change
  after_commit :update_product_stock_quantities, if: -> { saved_change_to_status? }

  # inventory.rb
  scope :assignable, -> { where(status: [:available, :in_transit], sale_order_id: nil) }


  private

  def track_status_change
    if status_changed?
      self.status_changed_at = Time.current
    end
  end

  def update_product_stock_quantities
    Products::UpdateStatsService.new(product).call
  end
end
