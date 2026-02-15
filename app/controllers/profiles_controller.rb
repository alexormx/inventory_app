# frozen_string_literal: true

class ProfilesController < ApplicationController
  layout 'customer'
  before_action :authenticate_user!

  def show
    @user = current_user
    @shipping_addresses = @user.shipping_addresses.order(created_at: :desc)
    @recent_orders = @user.sale_orders.order(created_at: :desc).limit(5)
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(profile_params)
      redirect_to profile_path, notice: 'Tu perfil ha sido actualizado correctamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.expect(user: %i[name phone address])
  end
end
