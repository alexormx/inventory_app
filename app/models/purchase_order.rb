class PurchaseOrder < ApplicationRecord
  include CustomIdGenerator

  belongs_to :user
  before_create :generate_custom_id

  has_many :purchase_order_items, dependent: :destroy, inverse_of: :purchase_order
  has_many :products, through: :purchase_order_items

  # Direct link by purchase_order_id to allow safe cascade deletes
  has_many :inventories, foreign_key: :purchase_order_id

  accepts_nested_attributes_for :purchase_order_items, allow_destroy: true

  # Allowed currencies for purchase orders
  CURRENCIES = %w[MXN USD EUR JPY GBP].freeze

  validates :order_date, presence: true
  validates :expected_delivery_date, presence: true
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_order_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :shipping_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :other_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :status, presence: true, inclusion: { in: ["Pending", "In Transit", "Delivered", "Canceled"]  }
  validate :expected_delivery_after_order_date
  validate :actual_delivery_after_expected_delivery

  after_update :update_inventory_status_based_on_order_status
  before_destroy :ensure_inventories_safe_or_cleanup

  # Asegurar consistencia de totales antes de validar / guardar
  before_validation :normalize_numeric_fields
  before_validation :recalculate_totals

  def may_be_deleted?
    !%w[Delivered Closed].include?(status)
  end

  private

  def expected_delivery_after_order_date
    if expected_delivery_date.present? && order_date.present? && expected_delivery_date < order_date
      errors.add(:expected_delivery_date, "must be after the order date")
    end
  end

  # -------------------- Cálculo de totales (callbacks) --------------------
  def normalize_numeric_fields
    self.shipping_cost = to_decimal(shipping_cost)
    self.tax_cost      = to_decimal(tax_cost)
    self.other_cost    = to_decimal(other_cost)
    self.subtotal      = to_decimal(subtotal)
    self.exchange_rate = to_decimal(exchange_rate.presence || 1)
    self.exchange_rate = 1 if currency == 'MXN'
  end

  def recalculate_totals
    lines = purchase_order_items.reject(&:marked_for_destruction?)

    # ✅ CORRECCIÓN: Subtotal = suma PURA de productos (qty * unit_cost), SIN extras
    # Los extras (shipping, tax, other) se suman después en total_order_cost
    computed_subtotal = lines.sum do |li|
      qty = li.quantity.to_d
      unit_cost = li.unit_cost.to_d
      qty * unit_cost
    end
    self.subtotal = computed_subtotal.round(2)

    # Total order cost (moneda original): subtotal + extras
    self.total_order_cost = (subtotal + shipping_cost + tax_cost + other_cost).round(2)

    # Total MXN (si la moneda no es MXN aplicar tipo de cambio)
    self.total_cost_mxn = if currency == 'MXN'
      total_order_cost
    else
      (total_order_cost * exchange_rate).round(2)
    end

    # Volumen y peso agregados (si los campos de línea existen)
    self.total_volume = lines.sum { |li| (li.respond_to?(:total_line_volume) && li.total_line_volume.present?) ? li.total_line_volume.to_d : 0 }.round(2)
    self.total_weight = lines.sum { |li| (li.respond_to?(:total_line_weight) && li.total_line_weight.present?) ? li.total_line_weight.to_d : 0 }.round(2)
  rescue => e
    Rails.logger.error "[PurchaseOrder#recalculate_totals] #{e.class}: #{e.message}"
  end

  def to_decimal(value)
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    0.to_d
  end

  def actual_delivery_after_expected_delivery
    return if actual_delivery_date.nil? || expected_delivery_date.nil?

    if actual_delivery_date < expected_delivery_date
      errors.add(:actual_delivery_date, "must be after or equal to expected delivery date")
    end
  end

  def generate_custom_id
    self.id = generate_unique_id("PO") if id.blank?
  end

  def update_inventory_status_based_on_order_status
    return unless saved_change_to_status?

    # No sobreescribir estados terminales ni manuales
    terminal = %i[sold reserved damaged lost returned scrap marketing pre_reserved pre_sold]

    scope = Inventory.where(purchase_order_id: self.id)
    case status
    when "Delivered"
      # Solo mover a available aquellos que están en tránsito o available
      scope.where(status: [:in_transit, :available]).update_all(
        status: Inventory.statuses[:available],
        status_changed_at: Time.current,
        updated_at: Time.current
      )
    when "Pending", "In Transit"
      scope.where(status: [:available, :in_transit]).update_all(
        status: Inventory.statuses[:in_transit],
        status_changed_at: Time.current,
        updated_at: Time.current
      )
    when "Canceled"
      scope.where.not(status: terminal).update_all(
        status: Inventory.statuses[:scrap],
        status_changed_at: Time.current,
        updated_at: Time.current
      )
    end
  end

  # Block if any locked; otherwise delete only free and allow destroy
  def ensure_inventories_safe_or_cleanup
    # ⬇️ plain relation, no association cache
    scope  = Inventory.where(purchase_order_id: self.id)

    locked = scope.where(status: [:reserved, :sold])
                  .or(scope.where.not(sale_order_id: nil))

    if locked.exists?
      errors.add(:base,
        "Cannot delete this purchase order: #{locked.count} inventory item(s) are reserved/sold or linked to a sale."
      )
      return false
    end

    scope.where(status: [:available, :in_transit], sale_order_id: nil).delete_all
  end

end
