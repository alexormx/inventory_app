# frozen_string_literal: true

module Admin
  class UserShippingAddressesController < ApplicationController
    before_action :authorize_admin!
    before_action :set_user
    before_action :set_address, only: %i[edit update destroy make_default]

    def index
      @addresses = @user.shipping_addresses.ordered
    end

    def show
      set_address
      if turbo_frame_request?
        render :show_modal
      else
        render :show
      end
    end

    def new
      @address = @user.shipping_addresses.new
      if turbo_frame_request?
        render :new_modal
      else
        render :new
      end
    end

    def edit
      if turbo_frame_request?
        render :edit_modal
      else
        render :edit
      end
    end

    def create
      @address = @user.shipping_addresses.new(address_params)
      if @address.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección creada.' }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              'address-modal-body',
              partial: 'admin/user_shipping_addresses/form',
              locals: { user: @user, address: @address }
            )
          end
          format.html { render :new, status: :unprocessable_entity }
        end
      end
    end

    def update
      if @address.update(address_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección actualizada.' }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              'address-modal-body',
              partial: 'admin/user_shipping_addresses/form',
              locals: { user: @user, address: @address }
            )
          end
          format.html { render :edit, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @address.destroy
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección eliminada.' }
      end
    end

    def make_default
      ShippingAddress.transaction do
        @user.shipping_addresses.update_all(default: false)
        @address.update!(default: true)
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección marcada como predeterminada.' }
      end
    rescue StandardError => e
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Error al marcar predeterminada: #{e.message}"
          render :index, status: :unprocessable_entity
        end
        format.html { redirect_to admin_user_shipping_addresses_path(@user), alert: "Error al marcar predeterminada: #{e.message}" }
      end
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_users_path, alert: 'Usuario no encontrado.'
    end

    def set_address
      @address = @user.shipping_addresses.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_shipping_addresses_path(@user), alert: 'Dirección no encontrada.'
    end

    def address_params
      params.expect(shipping_address: %i[label full_name line1 line2 city state postal_code country settlement municipality default])
    end
  end
end

