# app/controllers/admin/payments_controller.rb
class Admin::PaymentsController < ApplicationController
  def new
    @sale_order = SaleOrder.find_by!(id: params[:sale_order_id])
    @payment = @sale_order.payments.build
  end

  def create
    @payment = Payment.new(payment_params)

    if @payment.save
      # Recarga la orden completamente con pagos actualizados
      @sale_order = SaleOrder.includes(:payments).find(@payment.sale_order_id)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_sale_order_path(@sale_order), notice: "Payment added" }
      end
    else
      # Error: volver a mostrar el formulario dentro del modal
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "payment-modal-body",
            partial: "admin/payments/form",
            locals: { payment: @payment, sale_order: SaleOrder.find(@payment.sale_order_id) }
          )
        end

        format.html do
          redirect_to admin_sale_order_path(@payment.sale_order), alert: "Error adding payment"
        end
      end
    end
  end

  private

  def payment_params
    params.require(:payment).permit(:amount, :payment_method, :status, :paid_at, :sale_order_id)
  end
end

