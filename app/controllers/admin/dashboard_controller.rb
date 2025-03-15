class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  layout "admin"

  def index
    @total_products = Product.count
    @total_users = User.count
    @total_orders = PurchaseOrder.count
  end

  private
  def authorize_admin!
    redirect_to root_path, alert: "Not authorized." unless current_user.admin?
  end
end
