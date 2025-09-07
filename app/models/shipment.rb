class Shipment < ApplicationRecord
  belongs_to :sale_order, foreign_key: "sale_order_id", primary_key: "id"

  validates :tracking_number, presence: true
  validates :carrier, presence: true
  validates :estimated_delivery, presence: true
  validates :shipping_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Use the custom DateValidator
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }
  validate :actual_not_before_estimated

  before_update :update_last_status_change
  after_save :update_sale_order_totals_if_shipping_changed
  after_commit :sync_sale_order_status_from_shipment, if: -> { saved_change_to_status? }

  enum :status, [ :pending, :shipped, :delivered, :canceled, :returned ], default: :pending

  private

  def update_last_status_change
    if status_changed?
      self.last_update = Time.current
    end
  end
  
  def actual_not_before_estimated
    return if actual_delivery.blank? || estimated_delivery.blank?
    if actual_delivery < estimated_delivery
      errors.add(:actual_delivery, "no puede ser anterior a la fecha estimada")
    end
  end

  def update_sale_order_totals_if_shipping_changed
    if saved_change_to_shipping_cost?
      sale_order.update!(shipping_cost: shipping_cost)
      sale_order.recalculate_totals!
    end
  end

  def sync_sale_order_status_from_shipment
    so = sale_order
    return unless so
    case status
    when "delivered"
      # Promueve a Delivered solo si estaba Confirmed/Pending; el callback en SO ajusta inventario
      if so.status != "Delivered"
        so.update!(status: "Delivered")
      end
    when "shipped"
      # Cuando el envío pasa a shipped, marcamos la SO como 'In Transit'
  so.update!(status: "In Transit") unless so.status == "In Transit"
    when "pending", "returned", "canceled"
      # Si el envío deja de estar delivered, degradar a Confirmed (si fully_paid) o Pending
      if so.fully_paid?
        # Si venimos de Delivered o In Transit regresamos a Confirmed
        if ["Delivered", "In Transit"].include?(so.status)
          so.update!(status: "Confirmed")
        end
      else
        # Si no está fully_paid, volver a Pending desde Delivered/Confirmed/In Transit
        if ["Delivered", "Confirmed", "In Transit"].include?(so.status)
          so.update!(status: "Pending")
        end
      end
    end
    # Forzar broadcast del badge tras el cambio de Shipment (UI viva)
    html = ApplicationController.render(
      partial: "admin/sale_orders/status_badge",
      locals: { sale_order: so }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      ["sale_order", so.id],
      target: "sale_order_status_badge",
      html: html
    )
  rescue => e
    Rails.logger.error "[Shipment#sync_sale_order_status_from_shipment] #{e.class}: #{e.message}"
  end
end
