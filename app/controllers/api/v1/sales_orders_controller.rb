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

    # Compute and persist total_cost_mxn consistently for reporting/UI
    begin
      currency = so_attrs[:currency].to_s
      total_order_cost = BigDecimal(so_attrs[:total_order_cost].to_s)
      exchange_rate = BigDecimal((so_attrs[:exchange_rate].presence || 0).to_s)

      total_cost_mxn = if currency == 'MXN'
        total_order_cost
      elsif exchange_rate > 0
        total_order_cost * exchange_rate
      else
        0
      end

      so_attrs[:total_cost_mxn] = total_cost_mxn.round(2)
    rescue ArgumentError
      so_attrs[:total_cost_mxn] = 0
    end

    sales_order = SaleOrder.new(so_attrs)

    if sales_order.save
      render json: { status: "success", sales_order: sales_order }, status: :created
    else
      render json: { status: "error", errors: sales_order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def sales_order_params
    params.require(:sales_order).permit(:id, :order_date, :currency, :exchange_rate, :tax_cost, :shipping_cost, :other_cost, :subtotal, :total_order_cost, :status, :email, :expected_delivery_date, :actual_delivery_date)
  end
end
