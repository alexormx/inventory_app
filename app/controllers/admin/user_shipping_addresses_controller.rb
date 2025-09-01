class Admin::UserShippingAddressesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_user
  before_action :set_address, only: [:edit, :update, :destroy, :make_default]

  layout 'admin'

  def index
    @addresses = @user.shipping_addresses.ordered
    @address = @user.shipping_addresses.build
  end

  def create
    @address = @user.shipping_addresses.build(address_params)
    @address.default = true if @user.shipping_addresses.blank?
    if @address.save
      redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección guardada.'
    else
      @addresses = @user.shipping_addresses.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @address.update(address_params)
      redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección actualizada.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @address.destroy
    redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección eliminada.'
  end

  def make_default
    @address.update(default: true)
    redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección establecida como predeterminada.'
  end

  private
  def set_user
    @user = User.find(params[:user_id])
  end
  def set_address
    @address = @user.shipping_addresses.find(params[:id])
  end
  def address_params
    params.require(:shipping_address).permit(:label, :full_name, :line1, :line2, :city, :state, :postal_code, :country, :default)
  end
end
