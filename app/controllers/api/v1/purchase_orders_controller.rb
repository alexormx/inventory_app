class Api::V1::PurchaseOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/purchase_orders
  def create
    user = User.find_by(email: purchase_order_params[:email])
    unless user
      render json: { status: "error", message: "User not found for email #{purchase_order_params[:email]}" }, status: :unprocessable_entity and return
    end

    po_attrs = purchase_order_params.except(:email).merge(user_id: user.id)
    purchase_order = PurchaseOrder.new(po_attrs)

    if purchase_order.save
      render json: { status: "success", purchase_order: purchase_order }, status: :created
    else
      render json: { status: "error", errors: purchase_order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def purchase_order_params
    params.require(:purchase_order).permit(:id, :order_date, :currency, :exchange_rate, :tax_cost, :shipping_cost, :other_cost, :subtotal, :total_order_cost, :status, :email, :expected_delivery_date, :actual_delivery_date)
  end
end

