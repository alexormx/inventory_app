class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :product

  # Nota: agregar nuevos estatus siempre al final para no cambiar los IDs existentes
  enum :status, [
    :available,
    :reserved,
    :in_transit,
    :sold,
    :damaged,
    :lost,
    :returned,
    :scrap,
    :pre_reserved, # inventario en tránsito asignado a SO no pagada
    :pre_sold,     # inventario en tránsito asignado a SO pagada/confirmada
    :marketing     # piezas apartadas para marketing (manual)
    ], default: :available


  validates :purchase_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: Inventory.statuses.keys }


  before_update :track_status_change
  after_commit :update_product_stock_quantities, if: -> { saved_change_to_status? }

  # inventory.rb
  scope :assignable, -> { where(status: [:available, :in_transit], sale_order_id: nil) }
  scope :free,     -> { where(sale_order_id: nil, status: %w[available in_transit]) }
  scope :reserved, -> { where(status: :reserved) }
  scope :sold,     -> { where(status: :sold) }


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
