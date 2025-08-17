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
    rescue ArgumentError
      so_attrs[:total_tax] = 0
      so_attrs[:total_order_value] = 0
      so_attrs[:subtotal] = 0
      so_attrs[:discount] = 0
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
    params.require(:sales_order).permit(:id, :order_date, :subtotal, :tax_rate, :total_tax, :discount, :total_order_value, :status, :email, :notes)
  end
end
