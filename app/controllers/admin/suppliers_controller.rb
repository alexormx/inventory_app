class Admin::SuppliersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_supplier, only: [:edit, :update]

  def index
    @suppliers = User.where(role: "supplier").order(created_at: :desc)
  end

  def new
    @supplier = User.new(role: "supplier")
  end

  def create
    @supplier = User.new(supplier_params.merge(role: "supplier"))
    @supplier.password = Devise.friendly_token.first(12)

    if @supplier.save
      redirect_to admin_suppliers_path, notice: "Supplier created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @supplier.update(supplier_params)
      redirect_to admin_suppliers_path, notice: "Supplier updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_supplier
    @supplier = User.find(params[:id])
  end

  def supplier_params
    params.require(:user).permit(:name, :email, :phone, :address)
  end
end
