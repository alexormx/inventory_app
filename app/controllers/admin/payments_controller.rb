# app/controllers/admin/payments_controller.rb
class Admin::PaymentsController < ApplicationController
  def new
    @sale_order = SaleOrder.find_by!(id: params[:sale_order_id])
    @payment = @sale_order.payments.build
  end

  def create
    @payment = Payment.new(payment_params)
    if @payment.save
      redirect_to admin_sale_order_path(@payment.sale_order), notice: "Payment recorded"
    else
      render :new
    end
  end

  private

  def payment_params
    params.require(:payment).permit(:amount, :payment_method, :status, :paid_at, :sale_order_id)
  end
end
