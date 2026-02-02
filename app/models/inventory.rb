# frozen_string_literal: true

class Inventory < ApplicationRecord
  belongs_to :purchase_order, optional: true
  belongs_to :purchase_order_item, optional: true
  belongs_to :sale_order, optional: true
  belongs_to :sale_order_item, optional: true
  belongs_to :product
  belongs_to :inventory_location, optional: true

  # Fotos específicas para piezas no nuevas (coleccionables)
  has_many_attached :piece_images

  SOURCES = [
    'po_regular',      # creado desde PO regular
    'po_adjustment',   # creado desde PO de ajuste
    'manual',          # creado manualmente
    'ledger_adjustment' # creado desde ledger de ajustes
  ].freeze

  # Estatus que requieren ubicación física (están en bodega)
  STATUSES_REQUIRING_LOCATION = %w[available reserved pre_reserved].freeze

  # Estatus que NO requieren ubicación (ya no están físicamente en bodega)
  STATUSES_WITHOUT_LOCATION = %w[in_transit sold pre_sold lost scrap damaged marketing returned].freeze

  # Condiciones de coleccionables
  ITEM_CONDITIONS = {
    brand_new: 0,     # Nuevo de línea (stock renovable)
    misb: 1,          # Mint In Sealed Box - Descontinuado, sellado
    moc: 2,           # Mint On Card - Sellado en blister
    mib: 3,           # Mint In Box - Caja original, pudo abrirse
    mint: 4,          # Perfecto estado, abierto
    loose: 5,         # Sin empaque, suelto
    good: 6,          # Buen estado, desgaste menor
    fair: 7           # Aceptable, desgaste visible
  }.freeze

  CONDITION_LABELS = {
    'brand_new' => 'Nuevo (Sellado)',
    'misb' => 'MISB - Mint In Sealed Box',
    'moc' => 'MOC - Mint On Card',
    'mib' => 'MIB - Mint In Box',
    'mint' => 'Mint',
    'loose' => 'Loose (Suelto)',
    'good' => 'Good (Buen estado)',
    'fair' => 'Fair (Aceptable)'
  }.freeze

  # Nota: agregar nuevos estatus siempre al final para no cambiar los IDs existentes
  enum :status,
       { available: 0, reserved: 1, in_transit: 2, sold: 3, damaged: 4, lost: 5, returned: 6, scrap: 7, pre_reserved: 8, pre_sold: 9, marketing: 10 }, default: :available

  enum :item_condition, ITEM_CONDITIONS, default: :brand_new

  validates :purchase_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: Inventory.statuses.keys }

  # Asigna source automáticamente si viene de una PO y no se especificó
  before_validation :set_source_from_purchase_order, on: :create

  before_save :clear_sale_order_for_free_status, if: :will_change_status_to_free?
  before_save :clear_location_if_status_not_requires_it
  before_update :track_status_change
  after_save :log_sale_order_cleared_event, if: :sale_order_cleared?
  after_commit :update_product_stock_quantities, if: -> { saved_change_to_status? }
  after_commit :allocate_preorders_if_now_available, if: -> { saved_change_to_status? || saved_change_to_sale_order_id? }

  # inventory.rb
  scope :assignable, -> { where(status: %i[available in_transit], sale_order_id: nil) }
  scope :free,     -> { where(sale_order_id: nil, status: %w[available in_transit]) }
  scope :reserved, -> { where(status: :reserved) }
  scope :sold,     -> { where(status: :sold) }

  # Scopes para ubicación
  scope :requiring_location, -> { where(status: STATUSES_REQUIRING_LOCATION) }
  scope :not_requiring_location, -> { where(status: STATUSES_WITHOUT_LOCATION) }

  # Método de instancia para verificar si requiere ubicación
  def requires_location?
    STATUSES_REQUIRING_LOCATION.include?(status.to_s)
  end

  # Precio a mostrar: nuevo usa precio de producto, otras condiciones usan precio individual
  def display_price
    brand_new? ? product.selling_price : (selling_price || product.selling_price)
  end

  # Imágenes a mostrar: piezas no nuevas usan sus fotos, fallback a producto
  def display_images
    return piece_images if piece_images.attached? && piece_images.any?

    product.product_images
  end

  # Etiqueta de condición para mostrar
  def condition_label
    CONDITION_LABELS[item_condition.to_s] || item_condition.to_s.titleize
  end

  # ¿Es pieza de coleccionista (no nueva)?
  def collectible?
    !brand_new?
  end

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

  # Limpia la ubicación cuando el estatus cambia a uno que no requiere ubicación
  def clear_location_if_status_not_requires_it
    return unless will_save_change_to_status?
    return if requires_location?

    self.inventory_location_id = nil
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
