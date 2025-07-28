class ProductsController < ApplicationController
  layout "customer"
  def index
    @products = Product.where(status: "active")

    if params[:query].present?
      q = "%#{params[:query]}%"
      @products = @products.where("product_name ILIKE ? OR category ILIKE ? OR brand ILIKE ?", q, q, q)
    end

    @products = @products.order(:product_name)
  end

  def show
    @product = Product.friendly.find(params[:id])
  end
end
