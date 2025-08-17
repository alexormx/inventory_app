class Api::V1::SalesOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/sales_orders
  def create
    user = User.find_by(email: sales_order_params[:email])
    unless user
      render json: { status: "error", message: "User not found for email #{sales_order_params[:email]}" }, status: :unprocessable_entity and return
    end

    so_attrs = sales_order_params.except(:email).merge(user_id: user.id)

    # Compute totals
    begin
      subtotal = BigDecimal((so_attrs[:subtotal].presence || 0).to_s)
      tax_rate = BigDecimal((so_attrs[:tax_rate].presence || 0).to_s)
      discount = BigDecimal((so_attrs[:discount].presence || 0).to_s)
      shipping_cost = BigDecimal((so_attrs[:shipping_cost].presence || 0).to_s)

      total_tax = (subtotal * (tax_rate / 100)).round(2)
      # Include shipping_cost into total (legacy data sometimes only set shipping)
      total_order_value = (subtotal + total_tax + shipping_cost - discount).round(2)

      so_attrs[:total_tax] = total_tax
      so_attrs[:total_order_value] = total_order_value
      so_attrs[:subtotal] = subtotal.round(2)
      so_attrs[:discount] = discount.round(2)
      # shipping_cost is not a column on SaleOrder; it's only used to compute totals
    rescue ArgumentError
      so_attrs[:total_tax] = 0
      so_attrs[:total_order_value] = 0
      so_attrs[:subtotal] = 0
      so_attrs[:discount] = 0
      # ignore shipping_cost on parse errors
    end

    # Normalizar estado deseado (el que viene en el payload)
    mapping = {
      "pending" => "Pending",
      "confirmed" => "Confirmed",
      "shipped" => "Shipped",
      "delivered" => "Delivered",
      "canceled" => "Canceled",
      "cancelled" => "Canceled"
    }

    desired_status = if so_attrs[:status].present?
                       mapping[so_attrs[:status].to_s.strip.downcase] || so_attrs[:status].to_s.strip.capitalize
                     else
                       "Pending"
                     end

    response_extra = {}

    begin
      ActiveRecord::Base.transaction do
  # Solo pasar atributos que pertenecen realmente al modelo SaleOrder
  allowed = SaleOrder.attribute_names.map(&:to_sym)
  sale_order_attrs = so_attrs.slice(*allowed)

  # Crear inicialmente la orden en Pending para evitar validaciones que
  # requieran payment/shipment antes de que existan. Luego actualizamos
  # el estado final (see below).
  sale_order_attrs[:status] = "Pending"

  sales_order = SaleOrder.create!(sale_order_attrs)

        # Crear payment si el estado deseado es Confirmed o Delivered
        if %w[Confirmed Delivered].include?(desired_status)
          # Solo crear pago si el total de la orden es mayor a 0
          if sales_order.total_order_value.to_f > 0.0
            pm_param = params.dig(:sales_order, :payment_method).presence
            pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                          pm_param.to_s
                        else
                          "transferencia_bancaria"
                        end

            payment = sales_order.payments.create!(
              amount: sales_order.total_order_value,
              status: "Completed",
              payment_method: pm_mapped
            )

            response_extra[:payment] = payment
          else
            response_extra[:payment] = { skipped_for_zero_amount: true }
          end
        end

        # Crear shipment si el estado deseado es Delivered
        if desired_status == "Delivered"
          expected = begin
            if params.dig(:sales_order, :expected_delivery_date).present?
              Date.parse(params.dig(:sales_order, :expected_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          actual = begin
            if params.dig(:sales_order, :actual_delivery_date).present?
              Date.parse(params.dig(:sales_order, :actual_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          order_base_date = sales_order.order_date || Date.today
          expected ||= (order_base_date + 20)
          actual ||= expected

          tracking = params.dig(:sales_order, :tracking_number).presence || "A00000000MX"
          carrier = params.dig(:sales_order, :carrier).presence || "Local"

          shipment = sales_order.create_shipment!(
            tracking_number: tracking,
            carrier: carrier,
            estimated_delivery: expected,
            actual_delivery: actual,
            status: Shipment.statuses[:delivered]
          )

          response_extra[:shipment] = shipment
        end

        # Ahora actualizamos el estado al deseado (ya existen payment/shipment si se requieren)
        if desired_status != "Pending"
          # Recargar para asegurar que asociaciones persistan, y actualizar columna
          sales_order.reload
          sales_order.update_columns(status: desired_status)
        end

        render json: { status: "success", sales_order: sales_order, extra: response_extra }, status: :created and return
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { status: "error", errors: e.record.errors.full_messages }, status: :unprocessable_entity and return
    rescue StandardError => e
      render json: { status: "error", message: e.message }, status: :internal_server_error and return
    end
  end

  private

  def sales_order_params
  params.require(:sales_order).permit(:id, :order_date, :subtotal, :tax_rate, :total_tax, :discount, :total_order_value, :status, :email, :notes,
                     :shipping_cost, :tracking_number, :carrier, :expected_delivery_date, :actual_delivery_date, :payment_method)
  end
end
