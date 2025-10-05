class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :sale_order_item, optional: true
  belongs_to :product

  SOURCES = [
    "po_regular",      # creado desde PO regular
    "po_adjustment",   # creado desde PO de ajuste
    "manual",          # creado manualmente
    "ledger_adjustment" # creado desde ledger de ajustes
  ].freeze

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

  # Asigna source automáticamente si viene de una PO y no se especificó
  before_validation :set_source_from_purchase_order, on: :create

  before_update :track_status_change
  after_commit :update_product_stock_quantities, if: -> { saved_change_to_status? }
  after_commit :allocate_preorders_if_now_available, if: -> { saved_change_to_status? || saved_change_to_sale_order_id? }
  before_save :clear_sale_order_for_free_status, if: :will_change_status_to_free?

  # inventory.rb
  scope :assignable, -> { where(status: [:available, :in_transit], sale_order_id: nil) }
  scope :free,     -> { where(sale_order_id: nil, status: %w[available in_transit]) }
  scope :reserved, -> { where(status: :reserved) }
  scope :sold,     -> { where(status: :sold) }


  private

  def set_source_from_purchase_order
    return if source.present? || purchase_order_id.blank?
    # Usa el kind de la PO para distinguir ajuste vs regular
    self.source = purchase_order&.kind == "adjustment" ? "po_adjustment" : "po_regular"
  end

  def track_status_change
    if status_changed?
      self.status_changed_at = Time.current
    end
  end

  def update_product_stock_quantities
    Products::UpdateStatsService.new(product).call
  end

  def allocate_preorders_if_now_available
    return unless status == "available" && sale_order_id.nil? # libres
    # Calcular cuántas unidades nuevas se añadieron a available en este commit
    # Simplificación: 1 unidad por registro Inventory.
    begin
      Preorders::PreorderAllocator.new(product, newly_available_units: 1).call
    rescue => e
      Rails.logger.error "[Preorders] Allocation error for product=#{product_id} inv=#{id}: #{e.class} #{e.message}"
    end
  end

  def will_change_status_to_free?
    return false unless will_save_change_to_status?
    %w[available in_transit].include?(status.to_s)
  end

  # Cuando una pieza vuelve a estar libre (available o in_transit), se debe desasociar de la orden
  def clear_sale_order_for_free_status
    self.sale_order_id = nil
    self.sale_order_item_id = nil
    self.sold_price = nil
  end
end
