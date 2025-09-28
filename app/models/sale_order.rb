class SaleOrder < ApplicationRecord
  include CustomIdGenerator
  belongs_to :user

  STATUSES = [
    "Pending",
    "Confirmed",
    "In Transit",
    "Delivered",
    "Canceled",
    "Returned"
  ].freeze



  CANONICAL_STATUS = {
    "pending"     => "Pending",
    "confirmed"   => "Confirmed",
    "in_transit"  => "In Transit",
    "shipped"     => "In Transit",  # si llega “shipped”, lo mapeamos a In Transit
    "delivered"   => "Delivered",
    "canceled"    => "Canceled",
    "cancelled"   => "Canceled",
    "returned"    => "Returned"
  }.freeze


  has_many :inventories, class_name: "Inventory", foreign_key: :sale_order_id
  has_many :payments, dependent: :restrict_with_error
  has_one :shipment, foreign_key: "sale_order_id", dependent: :restrict_with_error
  has_many :sale_order_items, dependent: :destroy
  has_many :products, through: :sale_order_items

  accepts_nested_attributes_for :sale_order_items, allow_destroy: true

  validates :order_date, presence: true
  validates :subtotal, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :total_tax, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_order_value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate :ensure_payment_and_shipment_present
  validates :shipping_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_destroy :ensure_inventories_safe_or_release
  before_validation :set_default_status, on: :create
  before_validation :compute_financials
  before_validation :normalize_status
  before_create :generate_custom_id

  # Opcional: si cambias status a 'Canceled', libera lo reservado
  after_update :release_reserved_if_canceled, if: :saved_change_to_status?
  # Sincronizar estado del shipment cuando la orden pase a Delivered
  after_update :ensure_shipment_status_matches, if: :saved_change_to_status?
  # Sincronizar inventarios reservado<->vendido al alternar Pending/Confirmed
  after_update :sync_inventory_status_for_payment_change, if: :saved_change_to_status?
  # Garantizar que todos los inventarios ligados tengan sale_order_item_id tras guardar
  after_commit :backfill_inventory_so_item_links
  # Actualizar UI (status badge) por Turbo cuando cambie el estado
  after_commit :broadcast_status_change, if: -> { previous_changes.key?("status") }

  def total_paid
    payments.where(status: "Completed").sum(:amount)
  end

  def fully_paid?
    total_paid >= total_order_value
  end

  # ------ Agregados de volumen y peso ------
  def total_volume_cm3
    sale_order_items.sum { |i| i.volume_cm3.to_d }
  end

  def total_weight_gr
    sale_order_items.sum { |i| i.weight_gr.to_d }
  end

  def update_status_if_fully_paid!
    # Promueve Pending -> Confirmed si está totalmente pagada.
    # Si baja el pago, permite degradar desde Confirmed o Delivered -> Pending para habilitar edición.
    if fully_paid?
      update!(status: "Confirmed") if status == "Pending"
      # Si ya está Delivered y se mantiene fully_paid, no cambiamos aquí.
    else
      if ["Confirmed", "Delivered"].include?(status)
        update!(status: "Pending")
      end
    end
  end

  # Snapshot de totales calculados dinámicamente (sin mutar atributos)
  def compute_dynamic_totals
    return { subtotal: 0.to_d, tax: 0.to_d, total: 0.to_d } unless sale_order_items.exists?
    sub = sale_order_items.sum(<<~SQL).to_d
      COALESCE(total_line_cost,
               quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
    SQL
    rate = (tax_rate || 0).to_d
    disc = (discount || 0).to_d
    ship = (shipping_cost || 0).to_d
    tax = (sub * (rate/100)).round(2)
    total = (sub + tax + ship - disc).round(2)
    { subtotal: sub, tax: tax, total: total }
  end

  # Recalcula subtotal a partir de las líneas y vuelve a calcular impuestos y total.
  # Úsalo cuando cambien items, tax_rate, discount o shipping_cost.
  # public porque es llamado desde Shipment y SaleOrderItem callbacks.
  def recalculate_totals!(persist: true)
    return self unless sale_order_items.exists?
    sub = sale_order_items.sum(<<~SQL)
      COALESCE(total_line_cost,
               quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
    SQL
    self.subtotal = sub.to_d.round(2)
    compute_financials
    save(validate: false) if persist
    self
  end

  private

  def ensure_payment_and_shipment_present
    # Solo validar al transicionar a un estado que exige pago/envío.
    return unless saved_change_to_status?

    case status
    when "Confirmed"
      errors.add(:payment, "must exist to confirm the order") unless total_order_value.to_f == 0.0 || payments.any?
    when "Shipped"
      # Para marcar como Shipped requerimos pago y envío existente
      errors.add(:payment, "must exist to ship the order") unless total_order_value.to_f == 0.0 || payments.any?
      errors.add(:shipment, "must exist to ship the order") unless shipment.present?
    when "In Transit"
      # Permitir 'In Transit' sin exigir pago, pero debe existir shipment
      errors.add(:shipment, "must exist to set in transit") unless shipment.present?
    when "Delivered"
      errors.add(:payment, "must exist to deliver the order") unless total_order_value.to_f == 0.0 || payments.any?
      errors.add(:shipment, "must exist to deliver the order") unless shipment.present?
    end
  end

  def generate_custom_id
    self.id = generate_unique_id("SO") if id.blank?
  end

  def set_default_status
    self.status ||= "Pending"
  end

  # Calcula impuestos y total a partir de subtotal, tax_rate y discount.
  # Se ejecuta antes de validar para garantizar consistencia aunque el front no lo envíe.
  def compute_financials
    sub = (subtotal || 0).to_d
    rate = (tax_rate || 0).to_d
    disc = (discount || 0).to_d
    ship = (shipping_cost || 0).to_d
    if sub.zero? && rate.zero? && disc.zero? && ship.zero?
      if (total_order_value.nil? || total_order_value.to_d.zero?) && sale_order_items.loaded? ? sale_order_items.any? : sale_order_items.exists?
        recalculate_totals!(persist: false)
      end
      return if total_tax.present? && total_order_value.present?
    end
    self.total_tax = (sub * (rate / 100)).round(2)
    self.total_order_value = (sub + total_tax.to_d + ship - disc).round(2)
  end


    # Bloquea si hay vendidos; si todo está reservado, libera y permite borrar.
  def ensure_inventories_safe_or_release
    sold = inventories.where(status: %w[sold])
    if sold.exists?
      errors.add(:base, "No se puede eliminar: hay #{sold.count} artículo(s) vendidos en esta orden.")
      throw :abort
    end

    # Libera las reservadas
    inventories.where(status: %w[reserved pre_reserved pre_sold]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
      sale_order_item_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  def release_reserved_if_canceled
    return unless status == "Canceled"

  inventories.where(status: %w[reserved pre_reserved pre_sold]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
      sale_order_item_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  def ensure_shipment_status_matches
    return unless status == "Delivered"

    # Si existe shipment, forzamos su estado a delivered (usa el enum como símbolo)
    if shipment.present?
      begin
        shipment.update!(status: :delivered)
      rescue StandardError
        # no queremos que un fallo en el shipment impida otras actualizaciones
        Rails.logger.error("Failed to sync shipment status for SaleOrder ");
      end
    else
      # Crear un shipment por defecto si no existe, usando valores seguros
      begin
        order_base = order_date || Date.today
        est = order_base + 20
        create_shipment!(
          tracking_number: "A00000000MX",
          carrier: "Local",
          estimated_delivery: est,
          actual_delivery: est,
          status: Shipment.statuses[:delivered]
        )
      rescue StandardError
        Rails.logger.error("Failed to create default shipment for SaleOrder ")
      end
    end
  end

  # Cambiar inventarios cuando la orden se confirma (pago completo) o se regresa a pendiente
  def sync_inventory_status_for_payment_change
    previous, current = saved_change_to_status
    # Cubrimos transiciones entre Pending, Confirmed y Delivered para sincronizar sold/reserved y pre_*.
  case [previous, current]
  when ["Pending", "Confirmed"], ["Confirmed", "Delivered"], ["Pending", "Delivered"]
      # Promoción de cobro/entrega: reserved -> sold ; pre_reserved -> pre_sold
      inventories.where(status: [:reserved]).update_all(status: Inventory.statuses[:sold], status_changed_at: Time.current, updated_at: Time.current)
      inventories.where(status: [:pre_reserved]).update_all(status: Inventory.statuses[:pre_sold], status_changed_at: Time.current, updated_at: Time.current)
  when ["Confirmed", "Pending"], ["Delivered", "Confirmed"], ["Delivered", "Pending"]
      # Reversión (edición/corrección): sold -> reserved ; pre_sold -> pre_reserved
      inventories.where(status: [:sold]).update_all(status: Inventory.statuses[:reserved], status_changed_at: Time.current, updated_at: Time.current)
      inventories.where(status: [:pre_sold]).update_all(status: Inventory.statuses[:pre_reserved], status_changed_at: Time.current, updated_at: Time.current)
    else
      # Otras transiciones no afectan inventario
    end

    # Broadcast Turbo Stream para refrescar la tabla y totales (si la vista está abierta)
    begin
      Turbo::StreamsChannel.broadcast_replace_to(
        ["sale_order", id],
        target: "sale_order_items",
        partial: "admin/sale_orders/items_table",
        locals: { sale_order: self }
      )
    rescue => e
      Rails.logger.error "[SaleOrder#sync_inventory_status_for_payment_change] Broadcast error: #{e.message}"
    end
  end

  def backfill_inventory_so_item_links
    # Limitar al scope de esta orden para evitar operaciones globales
    Inventories::BackfillSaleOrderItemId.new(scope: inventories).call
  rescue => e
    Rails.logger.error "[SaleOrder#backfill_inventory_so_item_links] #{e.class}: #{e.message}"
  end

  def broadcast_status_change
    # Actualiza en vivo el badge dentro del frame con id "sale_order_status"
    Turbo::StreamsChannel.broadcast_update_to(
      ["sale_order", id],
      target: "sale_order_status",
      partial: "admin/sale_orders/status_badge",
      locals: { sale_order: self }
    )
  rescue => e
    Rails.logger.error "[SaleOrder#broadcast_status_change] #{e.class}: #{e.message}"
  end

  def normalize_status
    return if status.blank?
    key = status.to_s.strip.downcase.tr(" ", "_")
    self.status = CANONICAL_STATUS[key] || status
  end
end

