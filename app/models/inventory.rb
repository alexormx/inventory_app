# frozen_string_literal: true

class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :purchase_order_item, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :sale_order_item, optional: true
  belongs_to :product
  belongs_to :inventory_location, optional: true

  SOURCES = [
    'po_regular',      # creado desde PO regular
    'po_adjustment',   # creado desde PO de ajuste
    'manual',          # creado manualmente
    'ledger_adjustment' # creado desde ledger de ajustes
  ].freeze

  # Nota: agregar nuevos estatus siempre al final para no cambiar los IDs existentes
  enum :status,
       { available: 0, reserved: 1, in_transit: 2, sold: 3, damaged: 4, lost: 5, returned: 6, scrap: 7, pre_reserved: 8, pre_sold: 9, marketing: 10 }, default: :available

  validates :purchase_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: Inventory.statuses.keys }

  # Asigna source automáticamente si viene de una PO y no se especificó
  before_validation :set_source_from_purchase_order, on: :create

  before_save :clear_sale_order_for_free_status, if: :will_change_status_to_free?
  before_update :track_status_change
  after_save :log_sale_order_cleared_event, if: :sale_order_cleared?
  after_commit :update_product_stock_quantities, if: -> { saved_change_to_status? }
  after_commit :allocate_preorders_if_now_available, if: -> { saved_change_to_status? || saved_change_to_sale_order_id? }

  # inventory.rb
  scope :assignable, -> { where(status: %i[available in_transit], sale_order_id: nil) }
  scope :free,     -> { where(sale_order_id: nil, status: %w[available in_transit]) }
  scope :reserved, -> { where(status: :reserved) }
  scope :sold,     -> { where(status: :sold) }

  private

  def set_source_from_purchase_order
    return if source.present? || purchase_order_id.blank?

    # Usa el kind de la PO para distinguir ajuste vs regular
    self.source = purchase_order&.kind == 'adjustment' ? 'po_adjustment' : 'po_regular'
  end

  def track_status_change
    return unless status_changed?

    self.status_changed_at = Time.current

  end

  def update_product_stock_quantities
    Products::UpdateStatsService.new(product).call
  rescue StandardError => e
    Rails.logger.error "[Inventory#update_product_stock_quantities] #{e.class}: #{e.message}"
  end

  def allocate_preorders_if_now_available
    return unless status == 'available' && sale_order_id.nil? # libres

    # Calcular cuántas unidades nuevas se añadieron a available en este commit
    # Simplificación: 1 unidad por registro Inventory.
    begin
      Preorders::PreorderAllocator.new(product, newly_available_units: 1).call
    rescue StandardError => e
      Rails.logger.error "[Preorders] Allocation error for product=#{product_id} inv=#{id}: #{e.class} #{e.message}"
    end
  end

  def will_change_status_to_free?
    return false unless will_save_change_to_status?

    %w[available in_transit].include?(status.to_s)
  end

  # Cuando una pieza vuelve a estar libre (available o in_transit), se debe desasociar de la orden
  def clear_sale_order_for_free_status
    @will_clear_sale_order = sale_order_id.present? || sale_order_item_id.present? || sold_price.present?
    self.sale_order_id = nil
    self.sale_order_item_id = nil
    self.sold_price = nil
  end

  def sale_order_cleared?
    @will_clear_sale_order && sale_order_id.nil? && sale_order_item_id.nil?
  end

  def log_sale_order_cleared_event
    return unless sale_order_cleared?

    InventoryEvent.create!(
      inventory: self,
      product: product,
      event_type: 'sale_order_link_cleared',
      previous_sale_order_id: saved_change_to_sale_order_id&.first,
      new_sale_order_id: nil,
      previous_sold_price: saved_change_to_sold_price&.first,
      new_sold_price: nil,
      metadata: { reason: 'status_transition_to_free', new_status: status }
    )
  rescue StandardError => e
    Rails.logger.error "[Inventory#log_sale_order_cleared_event] #{e.class}: #{e.message}"
  ensure
    @will_clear_sale_order = false
  end
end
