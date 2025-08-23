# frozen_string_literal: true
module Audit
  # Audit::DeliveredOrdersDebtAudit
  # Recorre las SaleOrders en estado Delivered y detecta discrepancias entre:
  # total_order_value y la suma de pagos Completed + shipping (si existiera via shipment)
  # Actualmente la tabla sale_orders no guarda shipping, así que comparamos solo pagos.
  # Devuelve un struct con totales y detalle por orden.
  class DeliveredOrdersDebtAudit
    Result = Struct.new(:total_orders, :with_debt, :total_debt_amount, :details, keyword_init: true)

    def initialize(auto_fix: false, create_payments: false, payment_method: nil)
      @auto_fix = auto_fix
      @create_payments = create_payments
      # Fallback: primer método de pago definido si no se envía uno
      @payment_method = payment_method.presence || (Payment.payment_methods.keys.first if defined?(Payment))
    end

    def run(limit: nil, on_progress: nil)
      scope = SaleOrder.where(status: 'Delivered')
      scope = scope.limit(limit) if limit

      total_count = scope.count
      processed = 0
      details = []
      total_debt = 0.to_d

      scope.find_each.with_index do |so, idx|
        so_total = so.total_order_value.to_d
        paid = so.payments.where(status: 'Completed').sum(:amount).to_d
        missing = (so_total - paid).round(2)
        next if missing <= 0

        detail = {
          sale_order_id: so.id,
          user_id: so.user_id,
          order_date: so.order_date,
          total_order_value: so_total.to_s,
          total_paid: paid.to_s,
          missing_amount: missing.to_s
        }

        if @auto_fix && @create_payments
          begin
            so.payments.create!(amount: missing, status: 'Completed', paid_at: so.order_date + 5.days, payment_method: @payment_method)
            detail[:fixed] = true
          rescue StandardError => e
            detail[:fixed] = false
            detail[:error] = e.message
          end
        end

        total_debt += missing
        details << detail
        processed = idx + 1
        if on_progress
          begin
            on_progress.call(processed, total_count)
          rescue StandardError
            # Ignorar errores del callback para no interrumpir auditoría
          end
        end
      end

      Result.new(
        total_orders: total_count,
        with_debt: details.size,
        total_debt_amount: total_debt.to_s,
        details: details
      )
    end
  end
end
