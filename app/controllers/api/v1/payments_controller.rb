class Api::V1::PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/sales_orders/:sales_order_id/payments
  def create
    sales_order = SaleOrder.find_by(id: params[:sales_order_id])
    unless sales_order
      render json: { status: "error", message: "SaleOrder not found" }, status: :not_found and return
    end

    # Si ya está pagada completamente, no duplicar
    if sales_order.total_paid >= sales_order.total_order_value
      render json: { status: "success", message: "SaleOrder already fully paid", sales_order_id: sales_order.id }, status: :ok and return
    end

    # Método de pago (default transferencia_bancaria)
    pm_param = params.dig(:payment, :payment_method).presence || params.dig(:sales_order, :payment_method).presence
    pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                  pm_param.to_s
                else
                  "transferencia_bancaria"
                end

    # paid_at: order_date + 5 días
    paid_at_ts = begin
      base_date = sales_order.order_date || Date.today
      (base_date.to_time.in_time_zone + 5.days)
    rescue StandardError
      Time.zone.now
    end

    amount_missing = (sales_order.total_order_value - sales_order.total_paid).round(2)

    payment = sales_order.payments.new(
      amount: amount_missing,
      status: "Completed",
      payment_method: pm_mapped,
      paid_at: paid_at_ts
    )

    if payment.save
      # Si la SO estaba Pending y ya quedó pagada, el callback del modelo ya la promoverá a Confirmed
      render json: { status: "success", payment: payment, sales_order_id: sales_order.id }, status: :created
    else
      render json: { status: "error", errors: payment.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
