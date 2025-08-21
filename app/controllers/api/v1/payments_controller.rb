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

    # Derivar total desde las líneas si el total sigue en 0/nil
    items_total = begin
      sales_order.sale_order_items.sum(<<~SQL)
        COALESCE(total_line_cost,
                 quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
      SQL
    rescue
      0
    end.to_d.round(2)

    effective_total = if sales_order.total_order_value.to_f > 0.0
                         sales_order.total_order_value.to_d
                       else
                         items_total
                       end

    # Si el total efectivo > 0 pero las columnas siguen en 0, actualiza totales para consistencia
    if sales_order.total_order_value.to_f <= 0.0 && effective_total > 0
      begin
        sales_order.update_columns(
          subtotal: effective_total,
          total_tax: 0,
          total_order_value: effective_total,
          updated_at: Time.current
        )
        sales_order.reload
      rescue => e
        Rails.logger.error({ at: "Api::V1::PaymentsController#create:update_totals_from_items_error", id: sales_order.id, error: e.message }.to_json)
      end
    end

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

    # Si ya está pagada completamente y el total efectivo es > 0, no duplicar
    if sales_order.total_order_value.to_f > 0.0 && sales_order.total_paid >= sales_order.total_order_value
      render json: { status: "success", message: "SaleOrder already fully paid", sales_order_id: sales_order.id }, status: :ok and return
    end

    # Monto faltante con base en total efectivo
    amount_missing = if sales_order.total_order_value.to_f > 0.0
                       (sales_order.total_order_value - sales_order.total_paid).round(2)
                     else
                       (effective_total - sales_order.total_paid).round(2)
                     end

    # Si aún el total efectivo es 0 o el faltante <= 0, salir con 422 para no confundir
    if amount_missing <= 0
      render json: { status: "error", message: "No payable amount (total is zero or already covered)", totals: { effective_total: effective_total.to_s, order_total: sales_order.total_order_value.to_s, paid: sales_order.total_paid.to_s } }, status: :unprocessable_entity and return
    end

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
