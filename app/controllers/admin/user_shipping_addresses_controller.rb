module Admin
	class UserShippingAddressesController < ApplicationController
		before_action :authorize_admin!
		before_action :set_user
		before_action :set_address, only: [:edit, :update, :destroy, :make_default]

		def index
			@addresses = @user.shipping_addresses.order(created_at: :desc)
			render plain: @addresses.map { |a| "#{a.id}: #{a.full_name} #{a.line1}" }.join("\n")
		end

		def new
			@address = @user.shipping_addresses.new
			render plain: "new address form placeholder"
		end

		def create
			@address = @user.shipping_addresses.new(address_params)
			if @address.save
				redirect_to admin_user_shipping_address_path(@user, @address), notice: 'Dirección creada.'
			else
				render plain: @address.errors.full_messages.join(", "), status: :unprocessable_entity
			end
		end

		def edit
			render plain: "edit address form placeholder"
		end

		def update
			if @address.update(address_params)
				redirect_to admin_user_shipping_address_path(@user, @address), notice: 'Dirección actualizada.'
			else
				render plain: @address.errors.full_messages.join(", "), status: :unprocessable_entity
			end
		end

		def destroy
			@address.destroy
			redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección eliminada.'
		end

		def show
			set_address
			render plain: "#{@address.full_name} - #{@address.line1}" if @address
		end

		def make_default
			ShippingAddress.transaction do
				@user.shipping_addresses.update_all(default: false)
				@address.update!(default: true)
			end
			redirect_to admin_user_shipping_addresses_path(@user), notice: 'Dirección marcada como predeterminada.'
		rescue => e
			redirect_to admin_user_shipping_addresses_path(@user), alert: "Error al marcar predeterminada: #{e.message}"
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
			params.require(:shipping_address).permit(:label, :full_name, :line1, :line2, :city, :state, :postal_code, :country, :settlement, :municipality)
		end
	end
end

