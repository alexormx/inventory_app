class Admin::CustomersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_customer, only: [:edit, :update]

  def index
    @customers = User.where(role: "customer")
  end

  def new
    @customer = User.new(role: "customer")
  end

  def create
    @customer = User.new(user_params)
    @customer.role = "customer"
    @customer.password = Devise.friendly_token.first(12) # generate a random password

    if @customer.save
      redirect_to admin_customers_path, notice: "Customer created successfully."
    else
      flash.now[:alert] = "Failed to create customer."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # @customer is already set by the before_action
  end

  def update
    @customer = User.find(params[:id])
    if @customer.update(user_params)
      redirect_to admin_customers_path, notice: "Customer updated successfully."
    else
      flash.now[:alert] = "Failed to update customer."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_customer
    @customer = User.find(params[:id])
    unless @customer.role == "customer"
      redirect_to admin_customers_path, alert: "Not a customer."
    end
  end

  def user_params
    params.require(:user).permit(:name, :email, :phone, :address, :discount_rate, :created_offline, :notes)
  end
end
