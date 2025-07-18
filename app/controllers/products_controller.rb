class ProductsController < ApplicationController
  layout "customer"
  def index
    @products = Product.where(status: "active").order(:product_name)
  end

  def show
    @product = Product.friendly.find(params[:id])
  end
end
