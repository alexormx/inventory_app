class Api::V1::PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/sales_orders/:sales_order_id/payments
  def create
    sales_order = SaleOrder.find_by(id: params[:sales_order_id])
    unless sales_order
      render json: { status: "error", message: "SaleOrder not found" }, status: :not_found and return
    end

    # Si el total está en 0/nil intenta recalcular desde las líneas, sin condicionar a exists?, para romper ciclos
    if (sales_order.total_order_value.nil? || sales_order.total_order_value.to_f <= 0.0)
      begin
        before_total = sales_order.total_order_value
        sales_order.recalculate_totals!(persist: true)
        sales_order.reload
        Rails.logger.info({ at: "Api::V1::PaymentsController#create:recalc", sales_order_id: sales_order.id, before_total: before_total&.to_s, after_total: sales_order.total_order_value.to_s, items_count: sales_order.sale_order_items.count }.to_json)
      rescue => e
        Rails.logger.error({ at: "Api::V1::PaymentsController#create:recalc_error", sales_order_id: sales_order.id, error: e.message }.to_json)
      end
    end

    # Parámetros opcionales
    amount_param = begin
      raw = params.dig(:payment, :amount)
      raw.present? ? BigDecimal(raw.to_s) : nil
    rescue
      nil
    end

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

    # Logging de diagnóstico
  Rails.logger.info(
      {
        at: "Api::V1::PaymentsController#create",
        sales_order_id: sales_order.id,
        so_total: sales_order.total_order_value.to_s,
        so_total_paid: sales_order.total_paid.to_s,
        incoming_amount: amount_param&.to_s,
        status: sales_order.status
      }.to_json
    )

    # Si viene un monto explícito (por ejemplo desde la migración), úsalo como objetivo a cubrir.
    if amount_param && amount_param > 0
      missing_vs_param = (amount_param - sales_order.total_paid).round(2)

      if missing_vs_param <= 0
        render json: { status: "success", message: "SaleOrder already fully paid for provided amount", sales_order_id: sales_order.id }, status: :ok and return
      end

      payment = sales_order.payments.new(
        amount: missing_vs_param,
        status: "Completed",
        payment_method: pm_mapped,
        paid_at: paid_at_ts
      )

      if payment.save
        render json: { status: "success", payment: payment, sales_order_id: sales_order.id }, status: :created and return
      else
        render json: { status: "error", errors: payment.errors.full_messages }, status: :unprocessable_entity and return
      end
    end

    # Si ya está pagada completamente contra el total de la orden, no duplicar
    if sales_order.total_paid >= sales_order.total_order_value
      render json: { status: "success", message: "SaleOrder already fully paid", sales_order_id: sales_order.id }, status: :ok and return
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
