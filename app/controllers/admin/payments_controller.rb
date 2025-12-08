# frozen_string_literal: true

# app/controllers/admin/payments_controller.rb
module Admin
  class PaymentsController < ApplicationController
    def new
      @sale_order = SaleOrder.find(params[:sale_order_id])
      @payment = @sale_order.payments.build
    end

    def edit
      @payment = Payment.find(params[:id])
      @sale_order = @payment.sale_order
    end

    def create
      @payment = Payment.new(payment_params)

      if @payment.save
        # Recarga la orden completamente con pagos actualizados
        @sale_order = SaleOrder.includes(:payments).find(@payment.sale_order_id)
        # Forzar sincronización inmediata del estado (no depender del after_commit)
        begin
          @sale_order.update_status_if_fully_paid!
          @sale_order.reload
        rescue StandardError => e
          Rails.logger.warn("[PaymentsController#create] could not update SaleOrder status: #{e.class} #{e.message}")
        end

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_sale_order_path(@sale_order), notice: 'Payment added' }
        end
      else
        # Error: volver a mostrar el formulario dentro del modal
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              'payment-modal-body',
              partial: 'admin/payments/form',
              locals: { payment: @payment, sale_order: SaleOrder.find(@payment.sale_order_id) }
            )
          end

          format.html do
            redirect_to admin_sale_order_path(@payment.sale_order), alert: 'Error adding payment'
          end
        end
      end
    end

    def update
      @payment = Payment.find(params[:id])

      if @payment.update(payment_params)
        @sale_order = @payment.sale_order
        begin
          @sale_order.update_status_if_fully_paid!
          @sale_order.reload
        rescue StandardError => e
          Rails.logger.warn("[PaymentsController#update] could not update SaleOrder status: #{e.class} #{e.message}")
        end

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_sale_order_path(@sale_order), notice: 'Payment updated' }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              'payment-modal-body',
              partial: 'admin/payments/form',
              locals: { payment: @payment, sale_order: @payment.sale_order }
            )
          end
          format.html { redirect_to admin_sale_order_path(@payment.sale_order), alert: 'Error updating payment' }
        end
      end
    end

    def destroy
      @payment = Payment.find(params[:id])
      @sale_order = @payment.sale_order
      @payment.destroy

      @sale_order = SaleOrder.includes(:payments).find(@sale_order.id) # 🔥 recarga para tener los pagos actualizados
      begin
        @sale_order.update_status_if_fully_paid!
        @sale_order.reload
      rescue StandardError => e
        Rails.logger.warn("[PaymentsController#destroy] could not update SaleOrder status: #{e.class} #{e.message}")
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_sale_order_path(@sale_order), notice: 'Payment deleted successfully.' }
      end
    end

    private

    def payment_params
      params.expect(payment: %i[amount payment_method status paid_at sale_order_id])
    end
  end
end

