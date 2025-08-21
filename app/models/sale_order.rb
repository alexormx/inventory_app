class SaleOrder < ApplicationRecord
  include CustomIdGenerator
  belongs_to :user

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
  validates :status, presence: true, inclusion: { in: %w[Pending Confirmed Shipped Delivered Canceled] }
  validate :ensure_payment_and_shipment_present

  before_destroy :ensure_inventories_safe_or_release
  before_validation :set_default_status, on: :create
  before_validation :compute_financials
  before_create :generate_custom_id

  # Opcional: si cambias status a 'Canceled', libera lo reservado
  after_update :release_reserved_if_canceled, if: :saved_change_to_status?
  # Sincronizar estado del shipment cuando la orden pase a Delivered
  after_update :ensure_shipment_status_matches, if: :saved_change_to_status?

  def total_paid
    payments.where(status: "Completed").sum(:amount)
  end

  def fully_paid?
    total_paid >= total_order_value
  end

  def update_status_if_fully_paid!
    # Solo promover de Pending -> Confirmed cuando esté fully_paid.
    # No cambiar otros estados (por ejemplo Delivered) para evitar
    # sobrescribir un estado final con Confirmed.
    if fully_paid? && status == "Pending"
      update!(status: "Confirmed")
    elsif !fully_paid? && status == "Confirmed"
      update!(status: "Pending")
    end
  end

  private

  def ensure_payment_and_shipment_present
    case status
    when "Confirmed"
  errors.add(:payment, "must exist to confirm the order") unless total_order_value.to_f == 0.0 || payments.any?
    when "Shipped"
  errors.add(:payment, "must exist to ship the order") unless total_order_value.to_f == 0.0 || payments.any?
  errors.add(:shipment, "must exist to ship the order") unless shipment.present?
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
    # Asegurar valores numéricos
    sub = (subtotal || 0).to_d
    rate = (tax_rate || 0).to_d
    disc = (discount || 0).to_d

    # Si falta info mínima, no forzar cálculo
    if sub.zero? && rate.zero? && disc.zero?
      # Si hay líneas y total está 0/nil, intenta calcular desde las líneas
      if (total_order_value.nil? || total_order_value.to_d.zero?) && sale_order_items.loaded? ? sale_order_items.any? : sale_order_items.exists?
        recalculate_totals!(persist: false)
      end
      return if total_tax.present? && total_order_value.present?
    end

    self.total_tax = (sub * (rate / 100)).round(2)
    self.total_order_value = (sub + total_tax.to_d - disc).round(2)
  end

  # Recalcula subtotal a partir de las líneas y vuelve a calcular impuestos y total.
  # Úsalo cuando cambien items, tax_rate o discount.
  def recalculate_totals!(persist: true)
    sub = sale_order_items.sum(<<~SQL)
      COALESCE(total_line_cost,
               quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
    SQL
    self.subtotal = sub.to_d.round(2)
    compute_financials
    if persist
      save(validate: false)
    end
    self
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
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  def release_reserved_if_canceled
    return unless status == "Canceled"

  inventories.where(status: %w[reserved pre_reserved pre_sold]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
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
      rescue StandardError => e
        Rails.logger.error("Failed to create default shipment for SaleOrder ")
      end
    end
  end
end

