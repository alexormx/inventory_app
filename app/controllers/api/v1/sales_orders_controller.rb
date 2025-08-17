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

    # SaleOrder schema: subtotal, tax_rate (percentage), total_tax, total_order_value, discount
    # Compute total_tax and total_order_value if not provided
    begin
      subtotal = BigDecimal((so_attrs[:subtotal].presence || 0).to_s)
      tax_rate = BigDecimal((so_attrs[:tax_rate].presence || 0).to_s)
      discount = BigDecimal((so_attrs[:discount].presence || 0).to_s)

      total_tax = (subtotal * (tax_rate / 100)).round(2)
      total_order_value = (subtotal + total_tax - discount).round(2)

      so_attrs[:total_tax] = total_tax
      so_attrs[:total_order_value] = total_order_value
      so_attrs[:subtotal] = subtotal.round(2)
      so_attrs[:discount] = discount.round(2)

      # Normalizar status para cumplir con la validación (Pending, Confirmed, Shipped, Delivered, Canceled)
      if so_attrs[:status].present?
        mapping = {
          "pending" => "Pending",
          "confirmed" => "Confirmed",
          "shipped" => "Shipped",
          "delivered" => "Delivered",
          "canceled" => "Canceled",
          "cancelled" => "Canceled"
        }
        so_attrs[:status] = mapping[so_attrs[:status].to_s.strip.downcase] || so_attrs[:status].to_s.strip.capitalize
      else
        so_attrs[:status] = "Pending"
      end
    rescue ArgumentError
      so_attrs[:total_tax] = 0
      so_attrs[:total_order_value] = 0
      so_attrs[:subtotal] = 0
      so_attrs[:discount] = 0
    end

    sales_order = SaleOrder.new(so_attrs)

    response_extra = {}

    if sales_order.save
      # Si la orden llega como 'Delivered', crear shipment y un payment "Completed"
      if sales_order.status == "Delivered"
        # Parsear fechas pasadas en params (opcionales)
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

        expected ||= (sales_order.order_date + 20)
        actual ||= expected

        tracking = params.dig(:sales_order, :tracking_number).presence || "A00000000MX"
        carrier = params.dig(:sales_order, :carrier).presence || "Local"

        shipment = Shipment.new(
          sale_order_id: sales_order.id,
          tracking_number: tracking,
          carrier: carrier,
          estimated_delivery: expected,
          actual_delivery: actual,
          status: Shipment.statuses[:delivered]
        )

        shipment_saved = shipment.save
        response_extra[:shipment] = shipment_saved ? shipment : { errors: shipment.errors.full_messages }

        # Crear payment completado por el valor total de la orden
        payment_method = params.dig(:sales_order, :payment_method).presence || "transferencia_bancaria"
        payment = Payment.new(
          sale_order_id: sales_order.id,
          amount: sales_order.total_order_value,
          status: "Completed",
          payment_method: payment_method
        )

        payment_saved = payment.save
        response_extra[:payment] = payment_saved ? payment : { errors: payment.errors.full_messages }
      end

      render json: { status: "success", sales_order: sales_order, extra: response_extra }, status: :created
    else
      render json: { status: "error", errors: sales_order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def sales_order_params
  params.require(:sales_order).permit(:id, :order_date, :subtotal, :tax_rate, :total_tax, :discount, :total_order_value, :status, :email, :notes,
                     :shipping_cost, :tracking_number, :carrier, :expected_delivery_date, :actual_delivery_date, :payment_method)
  end
end
