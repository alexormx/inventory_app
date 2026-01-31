# frozen_string_literal: true

module Admin
  class PaymentMethodsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    layout 'admin'
    before_action :set_payment_method, only: %i[edit update destroy toggle_active]

    def index
      @payment_methods = PaymentMethod.ordered.page(params[:page]).per(20)
    end

    def new
      @payment_method = PaymentMethod.new(active: true, position: PaymentMethod.maximum(:position).to_i + 1)
    end

    def create
      @payment_method = PaymentMethod.new(payment_method_params)
      if @payment_method.save
        redirect_to admin_payment_methods_path, notice: 'Método de pago creado correctamente.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @payment_method.update(payment_method_params)
        redirect_to admin_payment_methods_path, notice: 'Método de pago actualizado.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @payment_method.destroy
      redirect_to admin_payment_methods_path, notice: 'Método de pago eliminado.'
    end

    def toggle_active
      @payment_method.update(active: !@payment_method.active)
      redirect_to admin_payment_methods_path, notice: "Método #{@payment_method.active ? 'activado' : 'desactivado'}."
    end

    private

    def set_payment_method
      @payment_method = PaymentMethod.find(params[:id])
    end

    def payment_method_params
      params.require(:payment_method).permit(:name, :code, :description, :instructions, :active, :position)
    end
  end
end
