# frozen_string_literal: true

module Admin
  class ShippingMethodsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    layout 'admin'
    before_action :set_shipping_method, only: %i[edit update destroy toggle_active]

    def index
      @shipping_methods = ShippingMethod.ordered.page(params[:page]).per(20)
    end

    def new
      @shipping_method = ShippingMethod.new(active: true, position: ShippingMethod.maximum(:position).to_i + 1)
    end

    def edit; end

    def create
      @shipping_method = ShippingMethod.new(shipping_method_params)
      if @shipping_method.save
        redirect_to admin_shipping_methods_path, notice: 'Método de envío creado correctamente.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @shipping_method.update(shipping_method_params)
        redirect_to admin_shipping_methods_path, notice: 'Método de envío actualizado.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @shipping_method.destroy
      redirect_to admin_shipping_methods_path, notice: 'Método de envío eliminado.'
    end

    def toggle_active
      @shipping_method.update(active: !@shipping_method.active)
      redirect_to admin_shipping_methods_path, notice: "Método #{@shipping_method.active ? 'activado' : 'desactivado'}."
    end

    private

    def set_shipping_method
      @shipping_method = ShippingMethod.find(params[:id])
    end

    def shipping_method_params
      params.expect(shipping_method: %i[name code description base_cost active position])
    end
  end
end
