# frozen_string_literal: true

class Shipment < ApplicationRecord
  belongs_to :sale_order, primary_key: 'id'

  validates :tracking_number, presence: true
  validates :carrier, presence: true
  validates :estimated_delivery, presence: true
  validates :shipping_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Use the custom DateValidator
  validates :actual_delivery, date: { after_or_equal_to: :estimated_delivery, allow_blank: true }
  validate :actual_not_before_estimated

  before_update :update_last_status_change
  after_update :sync_sale_order_status_from_shipment, if: :saved_change_to_status?
  after_save :update_sale_order_totals_if_shipping_changed

  enum :status, { pending: 0, shipped: 1, delivered: 2, canceled: 3, returned: 4 }, default: :pending

  private

  def update_last_status_change
    # En before_update usamos will_save_change_to_* para detectar cambios pendientes
    return unless will_save_change_to_status?

    self.last_update = Time.current
    
  end

  def actual_not_before_estimated
    return if actual_delivery.blank? || estimated_delivery.blank?

    return unless actual_delivery < estimated_delivery

    errors.add(:actual_delivery, 'no puede ser anterior a la fecha estimada')
    
  end

  def update_sale_order_totals_if_shipping_changed
    return unless saved_change_to_shipping_cost?

    sale_order.update!(shipping_cost: shipping_cost)
    sale_order.recalculate_totals!
    
  end

  # Cuando el estado del Shipment cambia, sincronizamos el SaleOrder relacionado
  def sync_sale_order_status_from_shipment
    so = sale_order
    return unless so

    current = status.to_s
    begin
      case current
      when 'pending'
        # Si el envío se regresa a pendiente, degradamos la orden:
        # - Si está totalmente pagada, a Confirmed; en otro caso, a Pending
        desired = so.fully_paid? ? 'Confirmed' : 'Pending'
        so.update!(status: desired) unless so.status == desired
      when 'shipped'
        # ESTRICTA B: si no hay pago y no hay crédito, no permitir pasar a In Transit
        # Permitir si está totalmente pagada o si tiene crédito habilitado
        credit_allowed = (so.user.respond_to?(:credit_enabled) && so.user.credit_enabled) || so.credit_override
        if so.fully_paid? || credit_allowed
          so.update!(status: 'In Transit') if %w[Canceled Returned].exclude?(so.status) && so.status != 'In Transit'
        else
          # revertir status del shipment a pending y registrar
          update_column(:status, Shipment.statuses[:pending])
          Rails.logger.warn "[Shipment#sync] Blocked shipped without payment or credit (sale_order_id=#{so.id})"
        end
      when 'delivered'
        # ESTRICTA B: si no hay pago y no hay crédito, no permitir Delivered
        credit_allowed = (so.user.respond_to?(:credit_enabled) && so.user.credit_enabled) || so.credit_override
        if so.fully_paid? || credit_allowed
          so.update!(status: 'Delivered') unless so.status == 'Delivered'
        else
          update_column(:status, Shipment.statuses[:shipped]) # mantén shipped si llegó aquí
          Rails.logger.warn "[Shipment#sync] Blocked delivered without payment or credit (sale_order_id=#{so.id})"
        end
      when 'canceled'
        # Si el envío se cancela y la orden no estaba entregada, cancelar la orden
        so.update!(status: 'Canceled') unless %w[Delivered Canceled].include?(so.status)
      when 'returned'
        so.update!(status: 'Returned') unless so.status == 'Returned'
      end
    rescue StandardError => e
      Rails.logger.error "[Shipment#sync_sale_order_status_from_shipment] #{e.class}: #{e.message} (sale_order_id=#{so.id})"
    end
  end
end
