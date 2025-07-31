class ProductsController < ApplicationController
  layout "customer"
  def index
    if params[:q].present?
      query = "%#{params[:q].downcase}%"
      @products = Product.where("status = ?", "active")
                        .where("LOWER(product_name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(brand) LIKE ?", query, query, query)
                        .order(:product_name)
    else
      @products = Product.where(status: "active").order(:product_name)
    end
  end

  def show
    @product = Product.friendly.find(params[:id])
  end
end
