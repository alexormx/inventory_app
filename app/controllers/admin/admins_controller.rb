class Admin::AdminsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_admin, only: [:edit, :update]

  def index
    @admins = User.where(role: "admin").order(created_at: :desc)
  end

  def new
    @admin = User.new(role: "admin")
  end

  def create
    @admin = User.new(admin_params.merge(role: "admin"))
    @admin.password = Devise.friendly_token.first(12)

    if @admin.save
      redirect_to admin_admins_path, notice: "Admin created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @admin.update(admin_params)
      redirect_to admin_admins_path, notice: "Admin updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def show
    @user = User.find(params[:id])
  end

  private

  def set_admin
    @admin = User.find(params[:id])
  end

  def admin_params
    params.require(:user).permit(:name, :email, :phone, :address)
  end
end