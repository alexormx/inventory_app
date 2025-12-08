# frozen_string_literal: true

module SaleOrders
  class EnsurePaymentService
    Result = Struct.new(:created, :created_amount, :skipped_reason, keyword_init: true)

    def initialize(sale_order, payment_method: 'transferencia_bancaria')
      @sale_order = sale_order
      @payment_method = payment_method
    end

    def call
      recalc_totals!

      effective_total = if @sale_order.total_order_value.to_f > 0.0
                          @sale_order.total_order_value.to_d
                        else
                          items_total
                        end

      paid = @sale_order.total_paid.to_d
      missing = (effective_total - paid).round(2)

      return Result.new(created: false, skipped_reason: 'no_payable_amount') if missing <= 0

      payment = @sale_order.payments.create!(
        amount: missing,
        status: 'Completed',
        payment_method: @payment_method,
        paid_at: paid_at_ts
      )

      Result.new(created: true, created_amount: payment.amount)
    end

    private

    def recalc_totals!
      @sale_order.recalculate_totals!(persist: true)
      @sale_order.reload
      return unless @sale_order.total_order_value.to_f <= 0.0 && @sale_order.sale_order_items.exists?

      it = items_total
      return unless it.positive?

      @sale_order.update_columns(subtotal: it, total_tax: 0, total_order_value: it, updated_at: Time.current)
      @sale_order.reload
        
      
    end

    def items_total
      @items_total ||= begin
        @sale_order.sale_order_items.sum(<<~SQL.squish).to_d.round(2)
          COALESCE(total_line_cost,
                   quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
        SQL
      rescue StandardError
        0.to_d
      end
    end

    def paid_at_ts
      base_date = @sale_order.order_date || Time.zone.today
      (base_date.to_time.in_time_zone + 5.days)
    rescue StandardError
      Time.zone.now
    end
  end
end
