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
  before_create :generate_custom_id

  # Opcional: si cambias status a 'Canceled', libera lo reservado
  after_update :release_reserved_if_canceled, if: :saved_change_to_status?

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

    # Bloquea si hay vendidos; si todo está reservado, libera y permite borrar.
  def ensure_inventories_safe_or_release
    sold = inventories.where(status: %w[sold])
    if sold.exists?
      errors.add(:base, "No se puede eliminar: hay #{sold.count} artículo(s) vendidos en esta orden.")
      throw :abort
    end

    # Libera las reservadas
    inventories.where(status: %w[reserved]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  def release_reserved_if_canceled
    return unless status == "Canceled"

    inventories.where(status: %w[reserved]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end
end

