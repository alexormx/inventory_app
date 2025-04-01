class Admin::InventoryController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @products_with_inventory = Product.includes(:inventory).order(:product_name)
  end

  def show
    @product = Product.find(params[:id])
    @inventory_items = @product.inventory.order(:status, :created_at)
  end
end