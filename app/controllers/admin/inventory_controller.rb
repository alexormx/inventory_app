class Admin::InventoryController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @products_with_inventory = Product.includes(:inventory)
  end

  def items
    @product = Product.find(params[:id])
    @inventory_items = @product.inventory.includes(:purchase_order)
  
    render partial: "admin/inventory/items", locals: { product: @product, items: @inventory_items }
  end
end