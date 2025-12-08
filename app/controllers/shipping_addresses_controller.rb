# frozen_string_literal: true

class ShippingAddressesController < ApplicationController
  layout 'customer'
  before_action :authenticate_user!
  before_action :set_address, only: %i[edit update destroy make_default]

  def index
    @addresses = current_user.shipping_addresses.ordered
    @address = ShippingAddress.new
  end

  def new
    @address = ShippingAddress.new
  end

  def edit; end

  def create
    @address = current_user.shipping_addresses.build(address_params)
    @address.default = true if current_user.shipping_addresses.blank?
    if @address.save
      if params[:return_to] == 'checkout_step2'
        redirect_to checkout_step2_path, notice: 'Dirección guardada.'
      else
        redirect_back_or_to shipping_addresses_path, notice: 'Dirección guardada.'
      end
    else
      @addresses = current_user.shipping_addresses.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @address.update(address_params)
      if params[:return_to] == 'checkout_step2'
        redirect_to checkout_step2_path, notice: 'Dirección actualizada.'
      else
        redirect_to shipping_addresses_path, notice: 'Dirección actualizada.'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @address.destroy
    if params[:return_to] == 'checkout_step2'
      redirect_to checkout_step2_path, notice: 'Dirección eliminada.'
    else
      redirect_to shipping_addresses_path, notice: 'Dirección eliminada.'
    end
  end

  def make_default
    @address.update(default: true)
    if params[:return_to] == 'checkout_step2'
      redirect_to checkout_step2_path, notice: 'Dirección establecida como predeterminada.'
    else
      redirect_to shipping_addresses_path, notice: 'Dirección establecida como predeterminada.'
    end
  end

  private

  def set_address
    @address = current_user.shipping_addresses.find(params[:id])
  end

  def address_params
    params.expect(shipping_address: %i[label full_name line1 line2 city state postal_code country default])
  end
end
